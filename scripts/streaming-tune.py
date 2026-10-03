#!/usr/bin/python3
"""Reversible Eclipse presets and bounded, read-only Mac streaming diagnostics."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import time

PROFILES = {
    'balanced': {'width':'1920','height':'1080','fps':'60','bitrate':'20000','videocfg':'2','videodec':'1','yuv444':'false','hdr':'false','enablevrr':'false','framepacing':'false','vsync':'true','showperfoverlay':'false','eclipse/localOverlay':'false'},
    'latency': {'width':'1920','height':'1080','fps':'60','bitrate':'20000','videocfg':'2','videodec':'1','yuv444':'false','hdr':'false','enablevrr':'false','framepacing':'false','vsync':'false','showperfoverlay':'false','eclipse/localOverlay':'false'},
    'vulkan-test': {'rendererbackend':'1'},
    'opengl-test': {'rendererbackend':'2'},
    'auto-renderer': {'rendererbackend':'0'},
}

def atomic(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd,tmp=tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd,'wb') as out:
            os.fchmod(out.fileno(),0o600);out.write(data);out.flush();os.fsync(out.fileno())
        os.replace(tmp,path)
        fd=os.open(path.parent,os.O_RDONLY|os.O_DIRECTORY)
        try:os.fsync(fd)
        finally:os.close(fd)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)

def read(path):
    try:return Path(path).read_text(errors='replace')[:32768].strip()
    except OSError:return None

def settings_parse(text):
    section=None;result={}
    for line in text.splitlines():
        header=re.fullmatch(r'\[([^\]]+)\]',line.strip())
        if header:section=header[1]
        elif section and '=' in line and not line.lstrip().startswith(('#',';')):
            key,value=line.split('=',1);key=key.strip()
            qualified=key if section=='General' else section+'/'+key
            if qualified in result:raise ValueError('Duplicate setting; use Eclipse settings to resolve it')
            result[qualified]=value.strip()
    return result

def settings_edit(text, changes):
    # QSettings writes eclipse/localOverlay as localOverlay in [eclipse].
    # Edit only owned keys; preserve raw host, theme and background sections.
    by_section={}
    for key,value in changes.items():
        section,name=key.split('/',1) if '/' in key else ('General',key)
        by_section.setdefault(section,{})[name]=value
    output=[];section=None;seen={};headers=set()
    def append(line):
        if output and not output[-1].endswith('\n'):output[-1]+='\n'
        output.append(line)
    def finish():
        for key,value in by_section.get(section,{}).items():
            if key not in seen.setdefault(section,set()) and value is not None:
                append(key+'='+value+'\n');seen[section].add(key)
    for line in text.splitlines(keepends=True):
        header=re.fullmatch(r'\[([^\]]+)\]',line.strip())
        if header:
            finish();section=header[1];headers.add(section)
        if section in by_section and '=' in line and not line.lstrip().startswith(('#',';')):
            key=line.split('=',1)[0].strip()
            if key in by_section[section]:
                seen.setdefault(section,set()).add(key)
                if by_section[section][key] is not None:append(key+'='+by_section[section][key]+'\n')
                continue
        output.append(line)
    finish()
    for missing,values in by_section.items():
        if missing not in headers and any(v is not None for v in values.values()):
            append('['+missing+']\n')
            for key,value in values.items():
                if value is not None:append(key+'='+value+'\n')
    return ''.join(output)

def idle():
    for directory in Path('/proc').glob('[0-9]*'):
        try:
            if directory.stat().st_uid!=os.getuid():continue
            executable=os.readlink(directory/'exe').removesuffix(' (deleted)')
            if Path(executable).name.lower() in ('vibemis','eclipse'):
                raise ValueError('Close Eclipse before changing its saved settings. Diagnostics can run while streaming.')
        except (FileNotFoundError,ProcessLookupError):pass

def tune(config, state_dir, mode):
    idle()
    if config.is_symlink():raise ValueError('Refusing a symlinked settings file')
    text=config.read_text() if config.exists() else ''
    if len(text)>1024*1024:raise ValueError('Settings file too large')
    current=settings_parse(text)
    receipt_path=state_dir/'preset.json'
    receipt=json.loads(receipt_path.read_text()) if receipt_path.exists() else {'before':{},'applied':{}}
    if receipt.get('pending'):
        pending=receipt['pending']
        matches=lambda values:all(current.get(key)==value for key,value in values.items())
        if matches(pending['new']):
            if pending['restore']:
                receipt_path.unlink()
                return {'message':'Interrupted restore completed.'}
            receipt['applied'].update(pending['new'])
        elif not matches(pending['old']):
            raise ValueError('Settings differ from both sides of an interrupted preset. Resolve them in Eclipse.')
        receipt.pop('pending')
        atomic(receipt_path,json.dumps(receipt).encode())
    # Protect changes made in Eclipse since this tool last wrote the owned keys.
    for key,value in receipt['applied'].items():
        if current.get(key)!=value:raise ValueError('Settings changed since tuning: '+key+'. Resolve in Eclipse rather than overwrite them.')
    if mode=='restore':
        if not receipt['applied']:raise ValueError('No preset snapshot to restore')
        receipt['pending']={'old':{k:current.get(k) for k in receipt['before']},'new':receipt['before'],'restore':True}
        atomic(receipt_path,json.dumps(receipt).encode())
        atomic(config,settings_edit(text,receipt['before']).encode())
        receipt_path.unlink()
        return {'message':'Previous streaming settings restored; unrelated settings preserved.'}
    changes=PROFILES[mode]
    for key in changes:
        if key not in receipt['before']:receipt['before'][key]=current.get(key)
    receipt['pending']={'old':{k:current.get(k) for k in changes},'new':changes,'restore':False}
    # Keep a recoverable snapshot before updating QSettings. No full-file replacement on restore.
    atomic(receipt_path,json.dumps(receipt).encode())
    atomic(config,settings_edit(text,changes).encode())
    receipt['applied'].update(changes);receipt.pop('pending')
    atomic(receipt_path,json.dumps(receipt).encode())
    return {'message':'Preset saved for next launch. Test on the Mac; this is not a measured performance result.','profile':mode,'values':changes}

def number(path):
    try:return int(read(path))
    except (TypeError,ValueError):return None

def snapshot(root=Path('/')):
    result={'cpus':{},'temperatures_c':{},'thermal_throttle_counts':{},'gpu':{},'power':{},'cpu_ticks':None,'core_ticks':{}}
    for path in sorted((root/'sys/devices/system/cpu').glob('cpu[0-9]*')):
        frequency={key:read(path/'cpufreq'/key) for key in ('scaling_driver','scaling_governor','scaling_cur_freq','scaling_min_freq','scaling_max_freq','energy_performance_preference')}
        if any(v is not None for v in frequency.values()):result['cpus'][path.name]=frequency
        for key in ('core_throttle_count','package_throttle_count'):
            value=number(path/'thermal_throttle'/key)
            if value is not None:result['thermal_throttle_counts'][path.name+'/'+key]=value
    for hw in (root/'sys/class/hwmon').glob('hwmon*'):
        name=read(hw/'name') or hw.name
        for sensor in hw.glob('temp*_input'):
            value=number(sensor)
            if value is not None and 0<=value<=150000:result['temperatures_c'][name+'/'+sensor.name]=value/1000
    for card in (root/'sys/class/drm').glob('card[0-9]*'):
        if '-' in card.name:continue
        values={key:read(card/key) for key in ('gt_cur_freq_mhz','gt_act_freq_mhz','gt_min_freq_mhz','gt_max_freq_mhz')}
        values.update({key:read(card/'device'/key) for key in ('vendor','device','gpu_busy_percent')})
        for gt in (card/'gt').glob('gt*'):
            for key in ('rps_act_freq_mhz','rps_cur_freq_mhz','rps_min_freq_mhz','rps_max_freq_mhz'):
                values[gt.name+'/'+key]=read(gt/key)
        result['gpu'][card.name]=values
    for device in (root/'sys/class/power_supply').glob('*'):
        result['power'][device.name]={key:read(device/key) for key in ('type','online','status','capacity','power_now')}
    text=read(root/'proc/stat')
    if text:
        fields=text.splitlines()[0].split()
        if len(fields)>=9 and fields[0]=='cpu':
            ticks=[int(x) for x in fields[1:9]]
            result['cpu_ticks']={'total':sum(ticks),'idle':ticks[3]+ticks[4]}
    if text:
        for line in text.splitlines():
            p=line.split()
            if len(p)>=9 and re.fullmatch(r'cpu[0-9]+',p[0]):
                ticks=[int(x) for x in p[1:9]]
                result['core_ticks'][p[0]]={'total':sum(ticks),'idle':ticks[3]+ticks[4]}
    memory=read(root/'proc/meminfo') or ''
    result['memory_kib']={line.split(':',1)[0]:int(line.split()[1]) for line in memory.splitlines() if line.split(':',1)[0] in ('MemAvailable','SwapTotal','SwapFree','Dirty','Writeback')}
    result['loadavg']=read(root/'proc/loadavg')
    return result

def command(args):
    try:
        env=dict(os.environ,LC_ALL='C',LANG='C',DISPLAY=os.environ.get('DISPLAY',':0'))
        if Path('/usr/lib64/dri-nonfree/iHD_drv_video.so').is_file():env['LIBVA_DRIVERS_PATH']='/usr/lib64/dri-nonfree'
        completed=subprocess.run(args,env=env,text=True,capture_output=True,timeout=8)
        return completed.returncode,(completed.stdout+completed.stderr)[:65536]
    except (OSError,subprocess.SubprocessError):return None,'Unavailable'

def assess(samples):
    findings=[]
    if not samples:return ['No samples; hardware/power status unknown.']
    first,last=samples[0],samples[-1]
    deltas={key:last['thermal_throttle_counts'][key]-value for key,value in first['thermal_throttle_counts'].items() if key in last['thermal_throttle_counts'] and last['thermal_throttle_counts'][key]>=value}
    if any(value>0 for value in deltas.values()):findings.append('CPU thermal throttle counters increased during capture.')
    if not deltas:findings.append('Thermal throttle counters unavailable; throttling has not been ruled out.')
    hottest=max((v for sample in samples for v in sample['temperatures_c'].values()),default=None)
    if hottest is not None and hottest>=90:findings.append('At least one sensor reached 90 C; inspect temperature/frequency trends, not temperature alone.')
    if any(p.get('type')=='Battery' and p.get('status')=='Discharging' for s in samples for p in s['power'].values()):findings.append('Battery discharging observed; compare the same stream on a working charger.')
    if not any(p.get('online')=='1' for s in samples for p in s['power'].values()):findings.append('No online external power source reported; charging/input power is unconfirmed.')
    if not findings:findings.append('No throttle-counter increase or hot-sensor warning observed in this interval. This does not certify hardware health or exclude transient power/driver limits.')
    return findings

def diagnose(seconds, root=Path('/'), sleeper=time.sleep, sampler=snapshot):
    samples=[]
    for index in range(seconds//2+1):
        sample=sampler(root);sample['elapsed_seconds']=index*2
        if samples and sample['cpu_ticks'] and samples[-1]['cpu_ticks']:
            old,new=samples[-1]['cpu_ticks'],sample['cpu_ticks'];delta=new['total']-old['total']
            if delta>0:sample['cpu_percent']=round(100*(1-(new['idle']-old['idle'])/delta),2)
        if samples:
            sample['core_cpu_percent']={}
            for core,new in sample.get('core_ticks',{}).items():
                old=samples[-1].get('core_ticks',{}).get(core)
                if old and new['total']>old['total']:
                    sample['core_cpu_percent'][core]=round(100*(1-(new['idle']-old['idle'])/(new['total']-old['total'])),2)
        samples.append(sample)
        if index<seconds//2:sleeper(2)
    report={'schema':1,'kernel':os.uname().release,'architecture':os.uname().machine,'seconds':seconds,'samples':samples,'findings':assess(samples)}
    code,display=command(['xrandr','--current'])
    report['active_display_modes']=[line.strip() for line in display.splitlines() if '*' in line and re.search(r'\d+\.\d+\*',line)] if code==0 else 'Unavailable'
    code,gl=command(['glxinfo','-B'])
    report['graphics']={key:line.split(':',1)[1].strip() for key in ('OpenGL vendor string','OpenGL renderer string','OpenGL version string') for line in gl.splitlines() if line.startswith(key+':')} if code==0 else {'status':'Unavailable'}
    if re.search(r'llvmpipe|softpipe',gl,re.I):report['findings'].append('Software OpenGL renderer detected; hardware rendering is not established.')
    render_nodes=sorted((root/'dev/dri').glob('renderD*'))
    if render_nodes:
        code,va=command(['vainfo','--display','drm','--device',str(render_nodes[0])])
        report['video_capabilities']=[line.strip() for line in va.splitlines() if ('Driver version' in line or 'VAProfile' in line)] if code==0 else 'Unavailable'
    else:report['video_capabilities']='No accessible render node'
    code,wifi=command(['nmcli','-t','-f','IN-USE,FREQ,CHAN,SIGNAL,SECURITY','device','wifi','list','--rescan','no'])
    report['active_wifi_radio']=[line for line in wifi.splitlines() if line.startswith('*:')][:8] if code==0 else 'Unavailable'
    report['services']={service:command(['systemctl','is-active',service])[1].strip()[:64] for service in ('thermald.service','power-profiles-daemon.service','tuned.service')}
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=[*PROFILES,'restore','status','diagnose','menu'])
    parser.add_argument('--seconds',type=int,default=30,help='Even number from 2 to 120; sample while a stream is running')
    args=parser.parse_args()
    if os.geteuid()==0:parser.error('Run as moonlight, without sudo; presets belong to that user')
    if args.mode=='menu':
        choices={'1':'status','2':'balanced','3':'latency','4':'opengl-test','5':'vulkan-test','6':'auto-renderer','7':'restore','8':'diagnose'}
        print('Eclipse streaming tuning\nBalanced/latency presets save 1080p60 HEVC hardware decode at 20 Mbps and disable both performance overlays; previous settings can be restored.\nLowest latency may tear. Renderer tests change only the renderer preference.\nClose Eclipse before changing saved settings; diagnostics run during a stream.\n1) Status  2) Balanced  3) Lowest latency  4) OpenGL test\n5) Vulkan test  6) Auto renderer  7) Restore  8) 30-second diagnostic  0) Exit')
        choice=input('Choose: ').strip()
        if choice not in choices:return
        args.mode=choices[choice]
    config=Path.home()/'.config/Vibemis Project/Vibemis.conf'
    folder=Path.home()/'.local/state/eclipseos/streaming'
    folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    with open(folder/'lock','a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        if args.mode=='diagnose':
            if not 2<=args.seconds<=120 or args.seconds%2:parser.error('--seconds must be even and between 2 and 120')
            result=diagnose(args.seconds)
            target=folder/'diagnostics.json';atomic(target,json.dumps(result,indent=2).encode())
            result={'report':str(target),'findings':result['findings']}
        elif args.mode=='status':
            saved=settings_parse(config.read_text()) if config.exists() else {}
            keys=set().union(*(p.keys() for p in PROFILES.values()))
            result={'settings':{key:saved.get(key,'default') for key in sorted(keys)},'restore_available':(folder/'preset.json').exists()}
        else:result=tune(config,folder,args.mode)
        print(json.dumps(result))

if __name__=='__main__':
    try:main()
    except (KeyboardInterrupt, EOFError):
        print('Cancelled.');raise SystemExit(130)
    except Exception as error:
        print(json.dumps({'error':str(error)[:512]}));raise SystemExit(1)
