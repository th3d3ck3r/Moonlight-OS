# Third-party software

Moonlight-OS is an integration/build project. It does not claim ownership of the software it builds into the image.

- **Fedora Linux 44** — Fedora Project; packages retain their individual licenses.
- **Moonlight-Qt** — moonlight-stream; GPL-3.0.
- **CocoOS** — Djingerr; fork of Moonlight-Qt; GPL-3.0.
- **snd_hda_macbookpro** — davidjo; third-party MacBook Cirrus audio driver. See upstream repository for its license and notices.
- **RPM Fusion packages** — individual package licenses apply.

Pinned revisions are listed in `SOURCES.lock`.

Moonlight-OS intentionally does not bundle FaceTime HD camera firmware or copy proprietary macOS firmware/NVRAM data. The camera is unnecessary for the streaming appliance, and the BCM4350 Wi-Fi path works with the kernel/firmware stack on the target MacBook.
