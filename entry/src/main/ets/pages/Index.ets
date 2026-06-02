import { media } from '@kit.MediaKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';

interface LrcLine {
  time: number;
  content: string;
}

@Entry
@Component
struct MusicPlayer {
  @State welcomeMessage: string = "音乐是心灵的避难所"; // 👈 固定文本，砍掉 Http
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPlaying: boolean = false;
  @State lrcData: LrcLine[] = [];
  @State currentLine: number = 0;
  @State rotateDegree: number = 0;
  @State volumeValue: number = 0.5;

  private mp3Path: string = "test_music.mp3";
  private lrcPath: string = "test_lrc.txt";

  private avPlayer: media.AVPlayer | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private timer: number = -1;

  async loadLrc() {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let uint8Array = await context.resourceManager.getRawFileContent(this.lrcPath);
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
      let fileDescriptor = await context.resourceManager.getRawFd(this.mp3Path);
      this.avPlayer.fdSrc = fileDescriptor;
    } catch (err) {
      console.error('加载失败');
    }
  }

  async aboutToAppear() {
    this.avPlayer = await media.createAVPlayer();
    this.setAVPlayerCallback();
    await this.loadLrc();
    this.prepareMusic();
    // 保留旋转动画
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
        result.push({ time: parseInt(match[1]) * 60 * 1000 + parseInt(match[2]) * 1000 + parseInt(match[3]), content: match[4].trim() });
      }
    });
    this.lrcData = result;
  }

  setAVPlayerCallback() {
    if (!this.avPlayer) return;
    this.avPlayer.on('stateChange', (state: string) => {
      if (state === 'initialized') this.avPlayer?.prepare();
      if (state === 'prepared') {
        this.duration = this.avPlayer?.duration || 0;
        this.avPlayer?.setVolume(this.volumeValue);
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
      // 保留基础高斯模糊背景
      Image($r('app.media.bg_cover')).width('100%').height('100%').objectFit(ImageFit.Cover).blur(15)

      Column() {
        Text(this.welcomeMessage).fontSize(14).fontColor('#FFFFFF').margin({ top: 40, bottom: 20 })

        // 纯黑胶展示，砍掉点击平滑切换歌词功能
        Column() {
          Text("Beauty And A Beat").fontSize(22).fontColor(Color.White).fontWeight(FontWeight.Bold).margin({ bottom: 4 })
          Text("Justin Bieber").fontSize(14).fontColor('#B3FFFFFF').margin({ bottom: 30 })

          Stack() {
            Circle().width('74%').aspectRatio(1).fill('#161616')
            Image($r('app.media.bg_cover')).width('46%').aspectRatio(1).borderRadius(1000).rotate({ angle: this.rotateDegree })
          }
        }.layoutWeight(1).justifyContent(FlexAlign.Center)

        // 传统底部组件块
        Column() {
          Row() {
            Text(this.formatTime(this.currentTime)).fontSize(11).fontColor('#FFFFFF')
            Slider({ value: this.currentTime, min: 0, max: this.duration, style: SliderStyle.InSet }).layoutWeight(1).selectedColor('#22C55E')
              .onChange((v) => this.avPlayer?.seek(v))
            Text(this.formatTime(this.duration)).fontSize(11).fontColor('#FFFFFF')
          }.width('90%').margin({ bottom: 15 })

          Row() {
            Button("▶").width(60).height(60).backgroundColor('#22C55E')
              .onClick(() => {
                if (this.isPlaying) this.avPlayer?.pause(); else this.avPlayer?.play();
                this.isPlaying = !this.isPlaying;
              })
          }.margin({ bottom: 30 })
        }.width('100%').backgroundColor('#FF191919')
      }
    }.width('100%').height('100%')
  }
}