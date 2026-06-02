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

  // 音量核心变量
  @State volumeValue: number = 0.5;
  @State isVolumePopupShow: boolean = false;

  // 【一多优化】：断点状态
  @State currentBreakpoint: string = 'sm';

  // 🔄 新增：实时屏幕方向状态 (默认竖屏)
  @State isLandscape: boolean = false;

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
      mp3Path: "huahai.mp3",
      lrcPath: "huahai_lrc.txt",
      cover: $r('app.media.huahai_cover')
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
      console.error('加载失败: ' + this.songList[this.currentIndex].mp3Path);
    }
  }

  async aboutToAppear() {
    this.fetchDailyQuote();
    this.avPlayer = await media.createAVPlayer();
    this.setAVPlayerCallback();

    await this.loadLrc();
    this.prepareMusic();

    this.timer = setInterval(() => {
      if (this.isPlaying) this.rotateDegree = (this.rotateDegree + 1.5) % 360;
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

  // 🔊 隐藏式音量气泡
  @Builder VolumePanel() {
    Row() {
      Text(this.volumeValue === 0 ? "🔇" : "🔊")
        .fontSize(14)
        .fontColor('#FFFFFF')
        .margin({ right: 8 })

      Slider({
        value: this.volumeValue * 100,
        min: 0,
        max: 100,
        style: SliderStyle.InSet
      })
        .width(110)
        .selectedColor('#FFFFFF')
        .trackColor('#40FFFFFF')
        .onChange((value) => {
          this.volumeValue = value / 100;
          this.avPlayer?.setVolume(this.volumeValue);
        })

      Text(`${Math.floor(this.volumeValue * 100)}%`)
        .fontSize(11)
        .fontColor('#E6FFFFFF')
        .margin({ left: 8 })
    }
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor('#A6111111')
    .borderRadius(24)
  }

  build() {
    Stack() {
      // 全屏流光背景
      Image(this.songList[this.currentIndex].cover)
        .width('100%').height('100%').objectFit(ImageFit.Cover).blur(35).opacity(0.65)

      Column() {
        // 1. 顶部一言
        Text(this.welcomeMessage)
          .fontSize(12)
          .fontColor('#B3FFFFFF')
          .fontWeight(FontWeight.Medium)
          .fontStyle(FontStyle.Italic)
          .margin({ top: this.isLandscape ? 15 : 45, bottom: this.isLandscape ? 10 : 20 }) // 👈 横屏时压缩顶部间距
          .padding({ left: 35, right: 35 })
          .textAlign(TextAlign.Center)

        // 2. 核心舞台区域
        GridRow({
          // 👈 核心修复：如果是横屏或者大屏，强制分配双栏（各占一半栅格）
          columns: { sm: 4, md: 8, lg: 12 },
          breakpoints: { value: ['520vp', '840vp'] }
        }) {

          // --- 左侧：唱片区 ---
          GridCol({ span: { sm: this.isLandscape ? 2 : 4, md: 4, lg: 6 } }) {
            // 👈 核心修复：横屏模式下强制展示唱片，不再因显示歌词而隐藏
            if (!this.showLrc || this.currentBreakpoint !== 'sm' || this.isLandscape) {
              Column() {
                Text(this.songList[this.currentIndex].title)
                  .fontSize(this.isLandscape ? 20 : 25) // 👈 横屏时字号微调
                  .fontColor(Color.White)
                  .fontWeight(FontWeight.Bold)
                  .margin({ bottom: 4 })

                Text(this.songList[this.currentIndex].singer)
                  .fontSize(13)
                  .fontColor('#B3FFFFFF')
                  .margin({ bottom: this.isLandscape ? 15 : 35 })

                Stack() {
                  Circle()
                    .width(this.isLandscape ? '50%' : '74%') // 👈 横屏时大幅缩小旋转盘，防止撑爆高度
                    .aspectRatio(1)
                    .fill('#0DFFFFFF')

                  Circle()
                    .width(this.isLandscape ? '48%' : '72%')
                    .aspectRatio(1)
                    .fill('#161616')
                    .shadow({ radius: 25, color: '#66000000' })

                  Image(this.songList[this.currentIndex].cover)
                    .width(this.isLandscape ? '30%' : '46%')
                    .aspectRatio(1)
                    .borderRadius(1000)
                    .rotate({ angle: this.rotateDegree })
                }
                .onClick(() => {
                  if (this.currentBreakpoint === 'sm' && !this.isLandscape) {
                    animateTo({ duration: 450 }, () => { this.showLrc = true })
                  }
                })
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
          }

          // --- 右侧：歌词区 ---
          GridCol({ span: { sm: this.isLandscape ? 2 : 4, md: 4, lg: 6 } }) {
            if (this.showLrc || this.currentBreakpoint !== 'sm' || this.isLandscape) {
              List({ scroller: this.scroller }) {
                ForEach(this.lrcData, (item: LrcLine, index: number) => {
                  ListItem() {
                    Text(item.content).width('100%').textAlign(TextAlign.Center)
                      .fontSize(this.currentLine === index ? 20 : 15) // 👈 横屏歌词字号微调
                      .fontWeight(this.currentLine === index ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(this.currentLine === index ? '#FFFFFF' : '#80FFFFFF')
                      .padding(this.isLandscape ? 8 : 14) // 👈 横屏时收窄上下内边距，容纳更多歌词
                  }
                })
              }
              .width('100%')
              .height('100%')
              .fadingEdge(true)
              .onClick(() => {
                if (this.currentBreakpoint === 'sm' && !this.isLandscape) {
                  animateTo({ duration: 450 }, () => { this.showLrc = false })
                }
              })
            }
          }

        }
        .layoutWeight(1)
        .onBreakpointChange((breakpoint: string) => {
          this.currentBreakpoint = breakpoint;
        })

        // --- 3. 隐形控制面板 ---
        Column() {
          // 播放进度条
          Row() {
            Text(this.formatTime(this.currentTime)).fontSize(10).fontColor('#99FFFFFF')
            Slider({ value: this.currentTime, min: 0, max: this.duration, style: SliderStyle.InSet })
              .layoutWeight(1)
              .selectedColor('#FFFFFF')
              .trackColor('#26FFFFFF')
              .onChange((v) => this.avPlayer?.seek(v))
            Text(this.formatTime(this.duration)).fontSize(10).fontColor('#99FFFFFF')
          }.width(this.isLandscape ? '70%' : '88%').margin({ bottom: 8 }) // 👈 横屏时进度条适当收窄

          // 控制主按键栏
          Row() {
            // 音量图标
            Text(this.volumeValue === 0 ? "🔇" : "🔊")
              .fontSize(20)
              .fontColor('#B3FFFFFF')
              .width(40)
              .textAlign(TextAlign.Start)
              .bindPopup(this.isVolumePopupShow, {
                builder: this.VolumePanel(),
                placement: Placement.Top,
                enableArrow: true,
                onStateChange: (e) => { this.isVolumePopupShow = e.isVisible }
              })
              .onClick(() => {
                this.isVolumePopupShow = !this.isVolumePopupShow;
              })

            Blank()

            // 中央控制三件套
            Row() {
              Text("⏮").fontSize(26).fontColor(Color.White)
                .onClick(() => this.changeSong(false))

              Stack() {
                Circle().width(48).height(48).fill('#FFFFFF') // 👈 稍微缩减按钮大小，适配横屏
                Text(this.isPlaying ? '‖' : '▶').fontSize(16).fontColor('#111111')
              }
              .margin({ left: 30, right: 30 })
              .onClick(() => {
                if (this.isPlaying) this.avPlayer?.pause(); else this.avPlayer?.play();
                this.isPlaying = !this.isPlaying;
              })

              Text("⏭").fontSize(26).fontColor(Color.White)
                .onClick(() => this.changeSong(true))
            }

            Blank()

            Text("").width(40)
          }
          .width(this.isLandscape ? '70%' : '88%')
          .margin({ bottom: this.isLandscape ? 12 : 30 }) // 👈 横屏时压缩底边距
        }
        .width('100%')
        .padding({ top: 10 })
        .backgroundColor('#10000000')
        .backdropBlur(25)
      }
    }
    .width('100%')
    .height('100%')
    // 👈 核心黑魔法：实时监听整个界面的宽高比！
    .onAreaChange((oldArea, newArea) => {
      let width = newArea.width as number;
      let height = newArea.height as number;
      // 如果宽大于高，说明被横过来了！
      this.isLandscape = width > height;
    })
  }
}