"""咒术回战 音频（第四轮 2026-09-30）：日语原声人声（动画/游戏，Demucs 去 BGM）+ 分层音效，输出 OGG。

项目根目录运行： python tools/build_jjk_audio.py [--ffmpeg PATH]
* 原始素材逐字节保存在 sources/jjk/audio/（.gdignore）。
  - 人声 *_voc.flac：YouTube 片段（yt-dlp --download-sections）→ htdemucs 分离出的 vocals 声部。
  - 其它：Mixkit 免费音效预览 mp3 / myinstants 动画原声。
* 人声链：高通 → 轻降噪 → 压缩 → loudnorm I=-14；音效链：分层叠混 → loudnorm（大招 -15，常用 -18）。
* 语音(v_*) 与音效分开：游戏里语音走角色独立语音通道（不叠、有冷却），音效每次都播。
* 结果写入 audio/characters/咒术回战/SOURCE.json 的 "sounds"（整体替换）。
Rights: 动画/游戏音频版权归原作者（© 芥見下々/集英社/MAPPA/Bandai Namco/SEGA）；Mixkit 音效按 Mixkit Free License。仅本地同人项目使用。
"""
import argparse, hashlib, json, os, re, subprocess

RAW = "sources/jjk/audio"
SND = "audio/characters/咒术回战"
YT = "https://www.youtube.com/watch?v="
MK = "https://assets.mixkit.co/active_storage/sfx/{0}/{0}-preview.mp3"
MI = "https://www.myinstants.com/media/sounds/"

# 人声片段：文件 -> (YouTube id, 起点, 终点, 说明)
VOC = {
    "gojo_intro_voc.flac": ("REIVs_EddVY", 177.4, 181.5, "ファンパレ 五条悟（CV 中村悠一）「天上天下唯我独尊」"),
    "gojo_blue_voc.flac": ("REIVs_EddVY", 97.9, 102.5, "ファンパレ 五条悟「術式順転 出力最大 蒼」"),
    "gojo_red_voc.flac": ("EyackbEPf2A", 0.0, 5.4, "TV 动画 第二期 五条悟「術式反転 赫」"),
    "gojo_purple_voc.flac": ("EyackbEPf2A", 191.6, 194.4, "TV 动画 第二期 五条悟「虚式 茈」"),
    "gojo_domain_voc.flac": ("vXrXrOzpOJw", 0.3, 8.3, "TV 动画 五条悟「領域展開 無量空処」"),
    "sukuna_domain_voc.flac": ("qDahjNZTalQ", 68.8, 73.6, "TV 动画 渋谷事変 宿儺（CV 諏訪部順一）「領域展開 伏魔御廚子」"),
    "sukuna_fuga_voc.flac": ("qDahjNZTalQ", 95.9, 98.2, "TV 动画 渋谷事変 宿儺「■（フーガ）」"),
    "black_flash_voc.flac": ("k0u6G8ClSKQ", 12.8, 14.4, "TV 动画「黒閃」"),
    "mahoraga_summon_voc.flac": ("KB_y-lYj_b4", 25.9, 32.8, "TV 动画 渋谷事変 伏黒恵「布瑠部由良由良 八握剣 異戒神将 魔虚羅」"),
}
MIX = {i: n for i, n in [
    (2608, "Air zoom vacuum"), (1465, "Vacuum swoosh transition"), (772, "Quick zoom impact"), (2655, "Fast impact blow"),
    (782, "Laser gun impact destruction"), (2758, "Explosive impact from afar"), (1693, "Shatter shot explosion"),
    (2155, "Impact of a strong punch"), (774, "Space impact"), (781, "Cinematic impact waves"), (2599, "Heavy electric shockwave impact"),
    (2782, "Epic impact afar explosion"), (166, "Fast small sweep transition"), (1486, "Cinematic tunnel reverb woosh"),
    (2630, "Terror sweep of darkness"), (658, "Choir magic shine"), (2793, "Quick magic sword slice"), (2792, "Fast sword whoosh"),
    (2152, "Quick knife slice cutting"), (2789, "Samurai Sword Impact"), (2788, "Sword cutting flesh"), (2199, "Body cutting impact"),
    (1327, "Big fire magic swoosh"), (1349, "Fast ignition fire"), (1338, "Fire spell with explosion"), (1343, "Fire explosion"),
    (3057, "Apocalyptic stomp impact"), (2291, "Eerie trailer horn transition"), (1331, "Big fire flame burning"),
    (2952, "Break tech impact"), (2183, "Glass hitting a metal"), (1021, "Cinematic glitch trailer"), (2795, "Heavy sword smashes metal"),
    (833, "Metal hammer hit"), (1528, "Magical stone slide"), (1293, "Fast thunder whoosh"), (1286, "Cinematic impact thunder"),
    (1508, "Lightning whip"), (1972, "Giant monster roar"), (14, "Aggressive monster beast roar")]}
SRC = {name: (YT + v + "  [%.1fs-%.1fs] → htdemucs vocals" % (a, b), d) for name, (v, a, b, d) in VOC.items()}
SRC.update({"%d.mp3" % i: (MK.format(i), "Mixkit #%d %s" % (i, n)) for i, n in MIX.items()})
SRC.update({
    "tmpfzpjrfx9.mp3": (MI + "tmpfzpjrfx9.mp3", "myinstants: TV 动画 宿儺「身の程を弁えろ… 痴れ者が」"),
    "sukuna-kai.mp3": (MI + "sukuna-kai.mp3", "myinstants: TV 动画 宿儺「解」"),
    "mahito-black-flash-effect-season-2-episode-20.mp3": (MI + "mahito-black-flash-effect-season-2-episode-20.mp3", "myinstants: TV 动画 渋谷事変 黒閃命中音"),
})

V, S, U = "voice", "sfx", "ult"
# 键 -> (类型, [(源, 起点, 时长, 延迟, 增益dB)], 淡出, 用途)
R = {
    # ---- 语音（全部日语原声） ----
    "v_gojo_intro": (V, [("gojo_intro_voc.flac", 0.3, 3.75, 0, 0)], 0.25, "五条悟登场「天上天下唯我独尊」"),
    "v_gojo_blue": (V, [("gojo_blue_voc.flac", 0.2, 4.3, 0, 0)], 0.3, "「術式順転 出力最大 蒼」"),
    "v_gojo_red": (V, [("gojo_red_voc.flac", 0.3, 1.45, 0, 0), ("gojo_red_voc.flac", 3.6, 1.0, 1.55, 0)], 0.2, "「術式反転…赫」（中间空白压缩）"),
    "v_gojo_purple": (V, [("gojo_purple_voc.flac", 0.05, 2.1, 0, 0)], 0.2, "「虚式 茈」"),
    "v_gojo_domain": (V, [("gojo_domain_voc.flac", 0.6, 1.5, 0, 0), ("gojo_domain_voc.flac", 5.4, 2.2, 1.7, 0)], 0.35, "「領域展開 無量空処」（停顿压缩到 0.2 秒）"),
    "v_sukuna_intro": (V, [("tmpfzpjrfx9.mp3", 0.25, 4.9, 0, 0)], 0.3, "宿傩登场「身の程を弁えろ… 痴れ者が」"),
    "v_sukuna_kai": (V, [("sukuna-kai.mp3", 0.25, 0.95, 0, 0)], 0.15, "「解」"),
    "v_sukuna_fuga": (V, [("sukuna_fuga_voc.flac", 0.05, 1.35, 0, 0)], 0.2, "「■（フーガ）」"),
    "v_sukuna_domain": (V, [("sukuna_domain_voc.flac", 0.1, 4.15, 0, 0)], 0.35, "「領域展開 伏魔御廚子」"),
    "v_black_flash": (V, [("black_flash_voc.flac", 0.1, 1.1, 0, 0)], 0.15, "「黒閃」"),
    "v_mahoraga_summon": (V, [("mahoraga_summon_voc.flac", 0.3, 1.5, 0, 0), ("mahoraga_summon_voc.flac", 3.05, 1.45, 1.6, 0), ("mahoraga_summon_voc.flac", 5.5, 0.95, 3.15, 0)], 0.25, "「布瑠部由良由良 八握剣 異戒神将 魔虚羅」"),
    # ---- 五条悟音效 ----
    "gojo_blue": (S, [("2608.mp3", 0.0, 1.25, 0, 0), ("1465.mp3", 0.4, 1.5, 0.0, -5), ("772.mp3", 0.05, 0.6, 0.0, -6)], 0.35, "苍：真空吸入"),
    "gojo_red": (S, [("2655.mp3", 0.0, 0.7, 0, 0), ("2608.mp3", 0.12, 0.8, 0.0, -5), ("782.mp3", 0.2, 1.1, 0.0, -7)], 0.3, "赫：发射"),
    "gojo_red_boom": (S, [("2758.mp3", 0.0, 2.0, 0, 0), ("1693.mp3", 0.0, 1.2, 0.0, -3), ("2155.mp3", 0.0, 0.5, 0.0, -2)], 0.6, "赫：命中爆裂"),
    "gojo_purple": (S, [("1465.mp3", 0.8, 0.8, 0, 0)], 0.1, "茈：蓄势（0.5 秒后发射）"),
    "gojo_purple_sfx": (U, [("774.mp3", 0.0, 3.2, 0, 0), ("781.mp3", 0.05, 3.5, 0.0, -3), ("2599.mp3", 3.4, 2.8, 0.0, -2), ("2782.mp3", 0.0, 2.8, 0.0, -7)], 1.2, "茈：发射贯穿"),
    "gojo_teleport": (S, [("166.mp3", 0.0, 0.7, 0, 0), ("2608.mp3", 0.15, 0.45, 0.0, -6)], 0.15, "瞬移"),
    "gojo_domain": (U, [("1486.mp3", 0.0, 5.0, 0, 0), ("2630.mp3", 0.0, 5.5, 0.0, -4), ("658.mp3", 0.0, 4.0, 0.3, -9), ("774.mp3", 0.0, 2.5, 0.0, -5)], 1.5, "无量空处展开"),
    # ---- 宿傩音效 ----
    "sukuna_dismantle": (S, [("2793.mp3", 0.0, 0.9, 0, 0), ("2792.mp3", 0.0, 0.3, 0.0, -4), ("2152.mp3", 0.0, 0.5, 0.02, -6)], 0.25, "解：斩击"),
    "sukuna_cleave": (S, [("2789.mp3", 0.0, 0.9, 0, 0), ("2788.mp3", 0.0, 0.6, 0.0, -3), ("2199.mp3", 0.0, 0.8, 0.05, -5), ("2199.mp3", 1.6, 0.7, 0.18, -6)], 0.3, "捌：连斩"),
    "sukuna_fuga": (S, [("1327.mp3", 0.0, 1.9, 0, 0), ("1349.mp3", 0.2, 1.8, 0.0, -5)], 0.5, "开：火矢成形"),
    "sukuna_fuga_boom": (U, [("1338.mp3", 0.0, 3.5, 0, 0), ("1343.mp3", 1.0, 3.0, 0.0, -4), ("3057.mp3", 0.0, 1.5, 0.0, -4)], 1.0, "开：命中爆炎"),
    "sukuna_domain": (U, [("3057.mp3", 0.0, 2.8, 0, 0), ("2291.mp3", 0.0, 6.0, 0.0, -3), ("1331.mp3", 0.2, 5.5, 0.4, -9)], 1.5, "伏魔御厨子展开"),
    "sukuna_world_slash_charge": (S, [("2599.mp3", 2.1, 1.38, 0, 0), ("1465.mp3", 0.3, 1.2, 0.1, -5)], 0.08, "世界斩蓄力（1.2 秒）"),
    "sukuna_world_slash": (U, [("2789.mp3", 0.0, 1.1, 0, 0), ("2952.mp3", 0.0, 1.3, 0.0, -2), ("1693.mp3", 0.0, 2.5, 0.0, -3), ("2599.mp3", 3.45, 2.9, 0.0, -4), ("2183.mp3", 0.0, 0.5, 0.0, -6)], 0.8, "世界斩：斩断空间"),
    # ---- 通用 / 式神 ----
    "black_flash_hit": (S, [("mahito-black-flash-effect-season-2-episode-20.mp3", 0.0, 1.5, 0, 0), ("2155.mp3", 0.0, 0.5, 0.0, -4), ("1021.mp3", 0.0, 0.6, 0.0, -7), ("2952.mp3", 0.0, 1.0, 0.0, -7)], 0.3, "黑闪命中"),
    "mahoraga_summon": (U, [("2291.mp3", 0.0, 4.0, 0, 0), ("3057.mp3", 0.0, 2.5, 0.0, -3)], 1.0, "魔虚罗降临"),
    "mahoraga_wheel": (S, [("2795.mp3", 0.0, 1.2, 0, 0), ("833.mp3", 0.0, 0.7, 0.0, 8), ("1528.mp3", 0.3, 1.9, 0.1, -6)], 0.4, "法阵转动（适应）"),
    "mahoraga_roar": (S, [("1972.mp3", 0.0, 3.1, 0, 0)], 0.6, "魔虚罗咆哮"),
    "agito_roar": (S, [("14.mp3", 0.0, 3.0, 0, 0)], 0.5, "嵌合暗兽 咆哮"),
    "agito_thunder": (S, [("1293.mp3", 0.0, 2.5, 0, 0), ("1286.mp3", 0.1, 2.4, 0.0, -3), ("1508.mp3", 0.0, 0.8, 0.0, -4)], 0.6, "鵺 落雷"),
}
LUFS = {V: -14, S: -18, U: -15}
VOICE_CHAIN = "highpass=f=90,lowpass=f=11500,afftdn=nf=-40,acompressor=threshold=-22dB:ratio=3:attack=5:release=90:makeup=2,"


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def build(ff, key, kind, layers, fo):
    total = max(d + t for _, _, t, d, _ in layers)
    args = [ff, "-y", "-hide_banner", "-loglevel", "error"]
    parts = []
    for i, (src, ss, t, d, g) in enumerate(layers):
        args += ["-ss", str(ss), "-t", str(t), "-i", os.path.join(RAW, src)]
        ms = int(d * 1000)
        edge = "afade=t=in:d=0.008,afade=t=out:st=%.3f:d=0.03," % max(t - 0.03, 0) if kind == V else ""
        parts.append("[%d:a]aresample=44100,aformat=channel_layouts=stereo,%svolume=%sdB,adelay=%d|%d,apad=whole_dur=%s[l%d]" % (i, edge, g, ms, ms, total, i))
    pre = VOICE_CHAIN if kind == V else ""
    post = "%safade=t=in:d=0.005,afade=t=out:st=%.3f:d=%s,loudnorm=I=%d:TP=-1.5:LRA=11,aresample=44100,alimiter=limit=0.84:level=false" % (pre, total - fo, fo, LUFS[kind])
    mix = "".join("[l%d]" % i for i in range(len(layers))) + "amix=inputs=%d:normalize=0:duration=longest," % len(layers) if len(layers) > 1 else "[l0]"
    fc = ";".join(parts) + ";" + mix + post + "[o]"
    out = os.path.join(SND, key + ".ogg")
    args += ["-filter_complex", fc, "-map", "[o]", "-t", "%.3f" % total, "-c:a", "libvorbis", "-q:a", "6", out]
    subprocess.run(args, check=True)
    return out, total, post


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffmpeg", default=os.environ.get("FFMPEG", "ffmpeg"))
    a = ap.parse_args(argv)
    used = {l[0] for _, ls, _, _ in R.values() for l in ls}
    missing = [n for n in used if not os.path.exists(os.path.join(RAW, n))]
    if missing: raise SystemExit("missing raw: %s" % missing)
    src_json = os.path.join(SND, "SOURCE.json")
    record = json.load(open(src_json, encoding="utf8")) if os.path.exists(src_json) else {}
    record["sounds"] = {}
    for key, (kind, layers, fo, use) in R.items():
        out, total, post = build(a.ffmpeg, key, kind, layers, fo)
        ls = [{"raw": RAW + "/" + src, "source": SRC[src][0], "desc": SRC[src][1], "raw_sha256": sha(os.path.join(RAW, src)),
               "trim_start": ss, "trim_seconds": t, "delay": d, "gain_db": g} for src, ss, t, d, g in layers]
        record["sounds"][key] = {"kind": kind, "layers": ls, "seconds": round(total, 2), "filters": post, "output": out.replace("\\", "/"),
                                 "output_sha256": sha(out), "language": "ja" if kind == V else "none (sfx)", "use": use}
        print("sound", key, round(total, 2), "s")
    for f in os.listdir(SND):
        if f.endswith(".ogg") and f[:-4] not in R:
            os.remove(os.path.join(SND, f))
            if os.path.exists(os.path.join(SND, f + ".import")): os.remove(os.path.join(SND, f + ".import"))
            print("removed stale", f)
    json.dump(record, open(src_json, "w", encoding="utf8"), ensure_ascii=False, indent=1)
    print("OK", len(R), "sounds")


if __name__ == "__main__":
    main()
