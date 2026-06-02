import { http } from '@kit.NetworkKit';
import { media } from '@kit.MediaKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

interface HitokotoResponse {
  hitokoto: string;
  from: string;
}

interface LrcLine {
  time: number;
  content: string;
}

interface SongItem {
  title: string;
  singer: string;
  mp3Path: string;
  lrcPath: string;
  cover: Resource;
}

@Entry
@Component
struct MusicPlayer {
  @State welcomeMessage: string = "正在连接云端音乐灵感...";
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPlaying: boolean = false;
  @State lrcData: LrcLine[] = [];
  @State currentLine: number = 0;
  @State rotateDegree: number = 0;
  @State showLrc: boolean = false;
  @State volumeValue: number = 0.5;

  private songList: SongItem[] = [
    { title: "Beauty And A Beat", singer: "Justin Bieber", mp3Path: "test_music.mp3", lrcPath: "test_lrc.txt", cover: $r('app.media.bg_cover') },
    { title: "花海", singer: "周杰伦", mp3Path: "huahai.mp3", lrcPath: "huahai_lrc.txt", cover: $r('app.media.huahai_cover') }
  ];

  @State currentIndex: number = 0;
  private avPlayer: media.AVPlayer | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private timer: number = -1;

  async fetchDailyQuote() {
    let httpRequest = http.createHttp();
    try {
      let response = await httpRequest.request("https://v1.hitokoto.cn/?c=i", { method: http.RequestMethod.GET, expectDataType: http.HttpDataType.OBJECT });
      if (response.responseCode === 200) {
        let data = response.result as HitokotoResponse;
        this.welcomeMessage = `${data.hitokoto} ——《${data.from}》`;
      }
    } catch (err) {
      this.welcomeMessage = "音乐是心灵的避难所";
    } finally {
      httpRequest.destroy();
    }
  }

  async changeSong(isNext: boolean) {
    if (!this.avPlayer) return;
    await this.avPlayer.reset();
    this.currentIndex = isNext ? (this.currentIndex + 1) % this.songList.length : (this.currentIndex - 1 + this.songList.length) % this.songList.length;
    await this.loadLrc();
    this.prepareMusic();
  }

  async loadLrc() {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let path = this.songList[this.currentIndex].lrcPath;
      let uint8Array = await context.resourceManager.getRawFileContent(path);
      let textDecoder = util.TextDecoder.create('utf-8');
      this.parseLrc(textDecoder.decode(uint8Array));
    } catch (e) {
      this.lrcData = [{ time: 0, content: "暂无歌词" }];
    }
  }

  async prepareMusic() {
    if (!this.avPlayer) return;
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let fileDescriptor = await context.resourceManager.getRawFd(this.songList[this.currentIndex].mp3Path);
      this.avPlayer.fdSrc = fileDescriptor;
    } catch (err) {
      console.error('加载失败');
    }
  }

  async aboutToAppear() {
    this.fetchDailyQuote();
    this.avPlayer = await media.createAVPlayer();
    this.setAVPlayerCallback();
    await this.loadLrc();
    this.prepareMusic();
    this.timer = setInterval(() => { if (this.isPlaying) this.rotateDegree = (this.rotateDegree + 1.5) % 360; }, 30);
  }

  aboutToDisappear() {
    if (this.avPlayer) this.avPlayer.release();
    clearInterval(this.timer);
  }

  parseLrc(lrcStr: string) {
    const lines = lrcStr.split('\n');
    const result: LrcLine[] = [];
    const pattern = /\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)/;
    lines.forEach(line => {
      const match = pattern.exec(line);
      if (match) {
        const minute = parseInt(match[1]);
        const second = parseInt(match[2]);
        const msStr = match[3];
        let finalMs = msStr.length === 2 ? parseInt(msStr) * 10 : parseInt(msStr);
        result.push({ time: minute * 60 * 1000 + second * 1000 + finalMs, content: match[4].trim() });
      }
    });
    this.lrcData = result;
    this.currentLine = 0;
    this.scroller.scrollToIndex(0);
  }

  setAVPlayerCallback() {
    if (!this.avPlayer) return;
    this.avPlayer.on('stateChange', (state: string) => {
      if (state === 'initialized') this.avPlayer?.prepare();
      if (state === 'prepared') {
        this.duration = this.avPlayer?.duration || 0;
        this.avPlayer?.setVolume(this.volumeValue);
        if (this.isPlaying) this.avPlayer?.play();
      }
    });
    this.avPlayer.on('timeUpdate', (time: number) => {
      this.currentTime = time;
      this.updateLrcIndex(time);
    });
  }

  updateLrcIndex(time: number) {
    for (let i = 0; i < this.lrcData.length; i++) {
      if (time >= this.lrcData[i].time && (i === this.lrcData.length - 1 || time < this.lrcData[i + 1].time)) {
        if (this.currentLine !== i) {
          this.currentLine = i;
          this.scroller.scrollToIndex(i, true, ScrollAlign.CENTER);
        }
        break;
      }
    }
  }

  formatTime(ms: number): string {
    let totalSeconds = Math.floor(ms / 1000);
    return `${Math.floor(totalSeconds / 60).toString().padStart(2, '0')}:${(totalSeconds % 60).toString().padStart(2, '0')}`;
  }

  build() {
    Stack() {
      Image(this.songList[this.currentIndex].cover).width('100%').height('100%').objectFit(ImageFit.Cover).blur(25)

      Column() {
        Text(this.welcomeMessage).fontSize(14).fontColor('#E6FFFFFF').margin({ top: 40, bottom: 20 }).padding({ left: 20, right: 20 }).textAlign(TextAlign.Center)

        // 核心舞台（仅支持单端手机模式切换）
        Column() {
          if (!this.showLrc) {
            Column() {
              Text(this.songList[this.currentIndex].title).fontSize(24).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ bottom: 4 })
              Text(this.songList[this.currentIndex].singer).fontSize(14).fontColor('#B3FFFFFF').margin({ bottom: 40 })

              Stack() {
                Circle().width('74%').aspectRatio(1).fill('#26000000')
                Circle().width('72%').aspectRatio(1).fill('#161616').shadow({ radius: 20, color: '#80000000' })
                Image(this.songList[this.currentIndex].cover).width('46%').aspectRatio(1).borderRadius(1000).rotate({ angle: this.rotateDegree })
              }.onClick(() => { animateTo({ duration: 400 }, () => { this.showLrc = true }) })
            }
          } else {
            List({ scroller: this.scroller }) {
              ForEach(this.lrcData, (item: LrcLine, index: number) => {
                ListItem() {
                  Text(item.content).width('100%').textAlign(TextAlign.Center)
                    .fontSize(this.currentLine === index ? 18 : 15)
                    .fontColor(this.currentLine === index ? '#22C55E' : '#B3FFFFFF') // 👈 回归原本的绿色高亮
                    .padding(12)
                }
              })
            }.width('100%').height('70%')
            .onClick(() => { animateTo({ duration: 400 }, () => { this.showLrc = false }) })
          }
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        // 底部传统控制台
        Column() {
          // 绿色进度条
          Row() {
            Text(this.formatTime(this.currentTime)).fontSize(11).fontColor('#B3FFFFFF')
            Slider({ value: this.currentTime, min: 0, max: this.duration, style: SliderStyle.InSet })
              .layoutWeight(1).selectedColor('#22C55E').trackColor('#40FFFFFF') // 👈 绿色进度条
              .onChange((v) => this.avPlayer?.seek(v))
            Text(this.formatTime(this.duration)).fontSize(11).fontColor('#B3FFFFFF')
          }.width('90%').margin({ bottom: 15 })

          // 常驻音量条与控制按钮
          Row() {
            Text("⏮").fontSize(28).fontColor(Color.White).onClick(() => this.changeSong(false))
            Stack() {
              Circle().width('54vp').height('54vp').fill('#22C55E') // 👈 绿色按钮
              Text(this.isPlaying ? '‖' : '▶').fontSize(18).fontColor(Color.White)
            }.margin({ left: 40, right: 40 })
            .onClick(() => {
              if (this.isPlaying) this.avPlayer?.pause(); else this.avPlayer?.play();
              this.isPlaying = !this.isPlaying;
            })
            Text("⏭").fontSize(28).fontColor(Color.White).onClick(() => this.changeSong(true))
          }.margin({ bottom: 20 })

          // 底部常驻音量条（无 Popup）
          Row() {
            Text("🔊").fontSize(16).fontColor('#B3FFFFFF').margin({ right: 10 })
            Slider({ value: this.volumeValue * 100, min: 0, max: 100, style: SliderStyle.InSet })
              .layoutWeight(1).selectedColor('#22C55E').trackColor('#40FFFFFF')
              .onChange((v) => { this.volumeValue = v / 100; this.avPlayer?.setVolume(this.volumeValue); })
          }.width('80%').margin({ bottom: 25 })
        }
        .width('100%').backgroundColor('#CC111111') // 👈 厚重底色底座
      }
    }.width('100%').height('100%')
  }
}