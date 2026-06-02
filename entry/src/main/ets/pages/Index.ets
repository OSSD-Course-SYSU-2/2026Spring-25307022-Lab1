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
  @State currentTime: number = 0;
  @State duration: number = 0;
  @State isPlaying: boolean = false;
  @State lrcData: LrcLine[] = [];

  private mp3Path: string = "test_music.mp3";
  private lrcPath: string = "test_lrc.txt";
  private avPlayer: media.AVPlayer | undefined = undefined;

  async loadLrc() {
    try {
      let context = getContext(this) as common.UIAbilityContext;
      let uint8Array = await context.resourceManager.getRawFileContent(this.lrcPath);
      let textDecoder = util.TextDecoder.create('utf-8');
      const lines = textDecoder.decode(uint8Array).split('\n');
      lines.forEach(line => {
        const match = /\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)/.exec(line);
        if (match) {
          this.lrcData.push({ time: parseInt(match[1]) * 60 * 1000 + parseInt(match[2]) * 1000, content: match[4].trim() });
        }
      });
    } catch (e) {
      this.lrcData = [{ time: 0, content: "暂无歌词" }];
    }
  }

  async aboutToAppear() {
    this.avPlayer = await media.createAVPlayer();
    this.avPlayer.on('stateChange', (state: string) => {
      if (state === 'initialized') this.avPlayer?.prepare();
      if (state === 'prepared') this.duration = this.avPlayer?.duration || 0;
    });
    this.avPlayer.on('timeUpdate', (time: number) => { this.currentTime = time; });
    await this.loadLrc();
    let context = getContext(this) as common.UIAbilityContext;
    this.avPlayer.fdSrc = await context.resourceManager.getRawFd(this.mp3Path);
  }

  build() {
    // v1.0.0：最纯粹的白底基础功能框架
    Column() {
      Text("Music Player v1.0.0").fontSize(20).margin(20).fontWeight(FontWeight.Bold)
      Text(`当前进度: ${Math.floor(this.currentTime/1000)}s / ${Math.floor(this.duration/1000)}s`).fontSize(16).margin(10)

      Button(this.isPlaying ? "暂停" : "播放").width(120).height(50).margin(20)
        .onClick(() => {
          if (this.isPlaying) this.avPlayer?.pause(); else this.avPlayer?.play();
          this.isPlaying = !this.isPlaying;
        })

      Text("歌词列表:").fontSize(14).margin(10).alignSelf(ItemAlign.Start)
      List() {
        ForEach(this.lrcData, (item: LrcLine) => {
          ListItem() { Text(item.content).fontSize(14).padding(6) }
        })
      }.width('100%').layoutWeight(1)
    }.width('100%').height('100%').backgroundColor(Color.White).padding(20)
  }
}