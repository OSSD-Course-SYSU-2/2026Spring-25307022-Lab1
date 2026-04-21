import { http } from '@kit.NetworkKit';
import { media } from '@kit.MediaKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

// --- 接口定义 ---
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
  // --- 状态变量 ---
  @State welcomeMessage: string = "正在连接云端音乐灵感...";
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPlaying: boolean = false;
  @State lrcData: LrcLine[] = [];
  @State currentLine: number = 0;
  @State rotateDegree: number = 0;
  @State showLrc: boolean = false;

  // --- 歌曲列表配置 ---
  private songList: SongItem[] = [
    {
      title: "Beauty And A Beat",
      singer: "Justin Bieber",
      mp3Path: "test_music.mp3",
      lrcPath: "test_lrc.txt",
      cover: $r('app.media.bg_cover')
    },
    {
      title: "花海",
      singer: "周杰伦",
      mp3Path: "huahai.mp3", // 你提到的文件名
      lrcPath: "huahai_lrc.txt", // 需确保 rawfile 中有此文件
      cover: $r('app.media.huahai_cover') // 需确保 media 中有此图片
    }
  ];

  @State currentIndex: number = 0;

  private avPlayer: media.AVPlayer | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private timer: number = -1;

  // --- 业务逻辑 ---

  async fetchDailyQuote() {
    let httpRequest = http.createHttp();
    try {
      let response = await httpRequest.request("https://v1.hitokoto.cn/?c=i", {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.OBJECT
      });
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

    // 重置播放器以切换源
    await this.avPlayer.reset();

    if (isNext) {
      this.currentIndex = (this.currentIndex + 1) % this.songList.length;
    } else {
      this.currentIndex = (this.currentIndex - 1 + this.songList.length) % this.songList.length;
    }

    await this.loadLrc();
    this.prepareMusic();
  }

  async loadLrc() {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let path = this.songList[this.currentIndex].lrcPath;
      let uint8Array = await context.resourceManager.getRawFileContent(path);
      let textDecoder = util.TextDecoder.create('utf-8');
      const rawLrc = textDecoder.decode(uint8Array);
      this.parseLrc(rawLrc);
    } catch (e) {
      this.lrcData = [{ time: 0, content: "暂无歌词" }];
    }
  }

  async prepareMusic() {
    if (!this.avPlayer) return;
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let path = this.songList[this.currentIndex].mp3Path;
      let fileDescriptor = await context.resourceManager.getRawFd(path);
      this.avPlayer.fdSrc = fileDescriptor;
    } catch (err) {
      console.error('加载失败，请检查文件名是否正确: ' + this.songList[this.currentIndex].mp3Path);
    }
  }

  async aboutToAppear() {
    this.fetchDailyQuote();
    this.avPlayer = await media.createAVPlayer();
    this.setAVPlayerCallback();

    await this.loadLrc();
    this.prepareMusic();

    this.timer = setInterval(() => {
      if (this.isPlaying) this.rotateDegree = (this.rotateDegree + 2) % 360;
    }, 30);
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
        const time = minute * 60 * 1000 + second * 1000 + finalMs;
        result.push({ time: time, content: match[4].trim() });
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
          this.scroller.scrollToIndex(i, true);
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
      // 动态模糊背景
      Image(this.songList[this.currentIndex].cover)
        .width('100%').height('100%').objectFit(ImageFit.Cover).blur(40).opacity(0.5)

      Column() {
        Text(this.welcomeMessage)
          .fontSize(13).fontColor('#CCFFFFFF').fontStyle(FontStyle.Italic)
          .margin({ top: 50, bottom: 20 }).padding({ left: 30, right: 30 })

        if (!this.showLrc) {
          Column() {
            Text(this.songList[this.currentIndex].title).fontSize(28).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ bottom: 8 })
            Text(this.songList[this.currentIndex].singer).fontSize(16).fontColor('#AAFFFFFF').margin({ bottom: 40 })

            Stack() {
              Circle().width(260).height(260).fill('#111111').shadow({ radius: 30, color: '#88000000' })
              Image(this.songList[this.currentIndex].cover)
                .width(170).height(170).borderRadius(85)
                .rotate({ angle: this.rotateDegree })
            }
            .onClick(() => { animateTo({ duration: 500 }, () => { this.showLrc = true }) })
          }.layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.scroller }) {
            ForEach(this.lrcData, (item: LrcLine, index: number) => {
              ListItem() {
                Text(item.content).width('100%').textAlign(TextAlign.Center)
                  .fontSize(this.currentLine === index ? 24 : 18)
                  .fontColor(this.currentLine === index ? '#4cd137' : '#AAFFFFFF').padding(15)
              }
            })
          }
          .layoutWeight(1)
          .onClick(() => { animateTo({ duration: 500 }, () => { this.showLrc = false }) })
        }

        // 控制面板
        Column() {
          Row() {
            Text(this.formatTime(this.currentTime)).fontSize(10).fontColor('#CCFFFFFF')
            Slider({ value: this.currentTime, min: 0, max: this.duration, style: SliderStyle.InSet })
              .layoutWeight(1).selectedColor('#4cd137')
              .onChange((v) => this.avPlayer?.seek(v))
            Text(this.formatTime(this.duration)).fontSize(10).fontColor('#CCFFFFFF')
          }.width('90%').margin({ bottom: 20 })

          Row() {
            Text("⏮").fontSize(35).fontColor(Color.White).onClick(() => this.changeSong(false))
            Stack() {
              Circle().width(64).height(64).fill('#4cd137')
              Text(this.isPlaying ? '‖' : '▶').fontSize(24).fontColor(Color.White)
            }.margin({ left: 40, right: 40 })
            .onClick(() => {
              if (this.isPlaying) this.avPlayer?.pause(); else this.avPlayer?.play();
              this.isPlaying = !this.isPlaying;
            })
            Text("⏭").fontSize(35).fontColor(Color.White).onClick(() => this.changeSong(true))
          }.margin({ bottom: 40 })
        }
        .width('100%').padding({ top: 30 }).backgroundColor('#20FFFFFF').backdropBlur(30).borderRadius({ topLeft: 40, topRight: 40 })
      }
    }.width('100%').height('100%')
  }
}