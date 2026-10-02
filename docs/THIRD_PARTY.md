# Third-party software

Moonlight-OS is an integration/build project. It does not claim ownership of the software it builds into the image.

- **Fedora Linux 44** — Fedora Project; packages retain their individual licenses.
- **Moonlight-Qt** — moonlight-stream; GPL-3.0.
- **CocoOS** — Djingerr; fork of Moonlight-Qt; GPL-3.0.
- **Vibemis** — navyas321; Moonlight-derived streaming client, GPL-3.0; native pinned source build.
- **Artemis** — wjbeckett; Moonlight-derived streaming client, GPL-3.0; native pinned source build.
- **Pegasus Frontend** — mmatyas; GPL-3.0 launcher; checksum-pinned Linux X11 package.
- **snd_hda_macbookpro** — davidjo; third-party MacBook Cirrus audio driver. See upstream repository for its license and notices.
- **RPM Fusion packages** — individual package licenses apply.

Pinned revisions are listed in `SOURCES.lock`.

Moonlight-OS intentionally does not bundle FaceTime HD camera firmware or copy proprietary macOS firmware/NVRAM data. The camera is unnecessary for the streaming appliance, and the BCM4350 Wi-Fi path works with the kernel/firmware stack on the target MacBook.
