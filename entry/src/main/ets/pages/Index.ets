import { media } from '@kit.MediaKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface LrcLine {
  time: number;
  content: string;
}

@Entry
@Component
struct MusicPlayer {
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPlaying: boolean = false;
  @State lrcData: LrcLine[] = [];
  @State currentLine: number = 0;
  @State rotateDegree: number = 0;
  @State showLrc: boolean = false; // 界面切换开关

  @State songTitle: string = "Beauty And A Beat";
  @State singerName: string = "Justin Bieber&Nicki Minaj";

  @State rawLrc: string = `[00:00.00] 正在准备音乐...
[00:02.00] 欢迎来到我的开源播放器
[00:05.00] 这是一首动听的 HarmonyOS 之歌
[00:10.00] 歌词正在随着音乐节奏滚动
[00:15.00] 大一学生也能做出酷炫的 App
[00:20.00] 提交到 GitHub 开启你的开发之路
[00:25.00] 坚持学习，顶峰相见`;

  private avPlayer: media.AVPlayer | undefined = undefined;
  private scroller: Scroller = new Scroller();
  private timer: number = -1;

  async aboutToAppear() {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let uint8Array = await context.resourceManager.getRawFileContent('test_lrc.txt');
      let textDecoder = util.TextDecoder.create('utf-8');
      this.rawLrc = textDecoder.decode(uint8Array);
    } catch (e) {
      console.warn('Using default demo lyrics');
    }
    this.parseLrc();
    this.initAVPlayer();

    this.timer = setInterval(() => {
      if (this.isPlaying) {
        this.rotateDegree = (this.rotateDegree + 1) % 360;
      }
    }, 30);
  }

  aboutToDisappear() {
    if (this.avPlayer) this.avPlayer.release();
    clearInterval(this.timer);
  }

  parseLrc() {
    const lines = this.rawLrc.split('\n');
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
  }

  async initAVPlayer() {
    try {
      this.avPlayer = await media.createAVPlayer();
      this.setAVPlayerCallback();
      let context = getContext(this) as common.UIAbilityContext;
      let fileDescriptor = await context.resourceManager.getRawFd('test_music.mp3');
      this.avPlayer.fdSrc = fileDescriptor;
    } catch (err) {
      console.error('Audio load failed');
    }
  }

  setAVPlayerCallback() {
    if (!this.avPlayer) return;
    this.avPlayer.on('stateChange', (state: string) => {
      if (state === 'initialized') this.avPlayer?.prepare();
      if (state === 'prepared') this.duration = this.avPlayer?.duration || 0;
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
      // 1. 动态背景层：根据 showLrc 切换背景色和图片
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          // 黑胶界面用深蓝色，歌词界面用深紫色，营造不同氛围
          colors: this.showLrc ? [['#4b1e99', 0.0], ['#2c0c61', 1.0]] : [['#1e3799', 0.0], ['#0c2461', 1.0]]
        })
        .animation({ duration: 800 }) // 背景色切换也平滑过渡

      Image($r('app.media.bg_cover'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        // 歌词界面背景更暗更模糊（100），黑胶界面稍亮稍清晰（40）
        .blur(this.showLrc ? 80 : 40)
        .opacity(this.showLrc ? 0.3 : 0.5)
        .animation({ duration: 800 })

      // 2. 内容层
      Column() {
        Text(this.showLrc ? "LYRICS" : "PLAYING")
          .fontSize(12)
          .fontColor('#88FFFFFF')
          .margin({ top: 50, bottom: 20 })
          .letterSpacing(3)

        // --- 核心切换区域 ---
        if (!this.showLrc) {
          // 【黑胶界面】内容
          Column() {
            Text(this.songTitle)
              .fontSize(28)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 8 })

            Text(this.singerName)
              .fontSize(16)
              .fontColor('#CCFFFFFF')
              .margin({ bottom: 40 })

            Stack({ alignContent: Alignment.Center }) {
              Circle().width(260).height(260).fill('#11ffffff').backdropBlur(10)
              Circle().width(240).height(240).fill('#111111')
                .shadow({ radius: 30, color: '#88000000', offsetX: 5, offsetY: 5 })
              Image($r('app.media.bg_cover'))
                .width(160)
                .height(160)
                .borderRadius(80)
                .rotate({ angle: this.rotateDegree })
                .border({ width: 4, color: '#222' })
            }
          }
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .transition({ type: TransitionType.Insert, opacity: 0, scale: { x: 0.8, y: 0.8 } })
          .onClick(() => {
            animateTo({ duration: 600, curve: Curve.EaseInOut }, () => { this.showLrc = true; })
          })
        } else {
          // 【歌词界面】内容
          List({ scroller: this.scroller }) {
            ForEach(this.lrcData, (item: LrcLine, index: number) => {
              ListItem() {
                Text(item.content)
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .fontSize(this.currentLine === index ? 24 : 18)
                  .fontColor(this.currentLine === index ? '#4cd137' : '#AAFFFFFF')
                  .fontWeight(this.currentLine === index ? FontWeight.Bold : FontWeight.Normal)
                  .padding({ top: 15, bottom: 15 })
                  .animation({ duration: 400 })
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
          .transition({ type: TransitionType.Insert, opacity: 0, scale: { x: 1.1, y: 1.1 } })
          .onClick(() => {
            animateTo({ duration: 600, curve: Curve.EaseInOut }, () => { this.showLrc = false; })
          })
        }

        // --- 底部控制台 ---
        Column() {
          Row() {
            Text(this.formatTime(this.currentTime)).fontSize(10).fontColor('#CCFFFFFF')
            Slider({ value: this.currentTime, min: 0, max: this.duration, style: SliderStyle.InSet })
              .layoutWeight(1)
              .blockColor(Color.White)
              .selectedColor('#4cd137')
              .trackColor('#33FFFFFF')
              .onChange((value) => {
                this.currentTime = value
                this.avPlayer?.seek(value)
              })
            Text(this.formatTime(this.duration)).fontSize(10).fontColor('#CCFFFFFF')
          }
          .width('90%')
          .margin({ bottom: 20 })

          Stack() {
            Circle().width(65).height(65).fill('#4cd137')
              .shadow({ radius: 20, color: '#804cd137', offsetX: 0, offsetY: 0 })
            Text(this.isPlaying ? '‖' : '▶').fontSize(25).fontColor(Color.White)
          }
          .onClick(() => {
            if (this.isPlaying) this.avPlayer?.pause()
            else this.avPlayer?.play()
            this.isPlaying = !this.isPlaying
          })
          .margin({ bottom: 40 })
        }
        .width('100%')
        .padding({ top: 25 })
        // 控制面板也可以根据背景微调
        .backgroundColor(this.showLrc ? '#10000000' : '#15FFFFFF')
        .backdropBlur(25)
        .borderRadius({ topLeft: 35, topRight: 35 })
      }
      .width('100%')
      .height('100%')
    }
  }
}