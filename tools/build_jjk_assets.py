"""Download + derive every 咒术回战 asset from the public web (user requirement).

Run from the project root:  python tools/build_jjk_assets.py [--ffmpeg PATH]

* Minecraft skins: 64x64 skin PNG from the listed page; the character visual is ONLY
  the face (8,8)-(16,16) with the hat overlay (40,8)-(48,16) composited, upscaled x16
  nearest-neighbour to 128x128.
* Sounds: myinstants.com public clips; trimmed/fade/loudness-normalised to OGG Vorbis.
* Originals are kept byte-for-byte in sources/jjk/ (with .gdignore so Godot skips them)
  and every URL/sha256/trim is written to SOURCE.json next to the derived files.
Rights: fan uploads of copyrighted anime audio / community skins. Kept for this local
fan project with provenance only; NOT cleared for redistribution. See SOURCE.json.
"""
import argparse, base64, hashlib, io, json, os, re, subprocess, sys, urllib.request

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36"
IMG_DIR = "Images/characters/动漫/咒术回战"
SND_DIR = "audio/characters/咒术回战"
RAW_DIR = "sources/jjk"

SKINS = {
    # key: (page url, how, direct texture url or None, author/uploader note)
    "五条悟": ("https://mc-skins.com/skins/gojo-satoru-5", "mc_skins_embedded", None, "mc-skins.com 'Gojo Satoru #5'"),
    "宿傩": ("https://mc-skins.com/skins/ryomen-sukuna", "mc_skins_embedded", None, "mc-skins.com 'Ryomen Sukuna'"),
    "魔虚罗": ("https://www.minecraftskins.com/skin/22202420/grand-general-mahoraga---jujutsu-kaisen/", "direct",
             "https://www.minecraftskins.com/uploads/skins/2023/12/23/grand-general-mahoraga---jujutsu-kaisen-22202420.png",
             "minecraftskins.com 'Grand General Mahoraga - Jujutsu Kaisen' by Chendo"),
    "嵌合暗兽": ("https://www.minecraftskins.com/skin/24346826/agito-jjk/", "direct",
              "https://www.minecraftskins.com/uploads/skins/2026/09/19/agito-jjk-24346826.png",
              "minecraftskins.com 'Agito JJK' by Stolas6922"),
}

# mc-skins.com answers 403 to some networks (seen on the Windows build host). These are the
# exact bytes of the embedded data-skin PNG fetched from the same page by the agent sandbox
# on 2026-09-28; used ONLY when the live fetch fails, and recorded as such in SOURCE.json.
FALLBACK_SKIN_B64 = {
    "五条悟": "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAFRklEQVR4Xu2aS4/cRBSFRwwSC8RLsIlAisQS2LKCfwC/jt/ChkggUKKQhEcGkonCJKOBRCCIxAKFDauij3uOc/urKj+6PT3dkz7S6bLr3irfc11ll+3e2+vB8b0/UxcPvn+QHj18VsZtlexv6yCRt6+fFCmbhD7545+2jNsq2d/WwWe6JD4mIH33+QIvVAIoniOgEX3vi0XO6p6fBEjw8c2Ufr8zp7ZndRcmAaUkuD4TjySwv61DSXxMwnORgC62878wBWRjf8uCx6V9abDjdZPx1LBsu16oM12sXMZtH+ws7YynhFp7+g1B1k6dxcXLv0//a7ctoHafj3a1UdvY1xD7QjABsqvsiy/69sHHX6h0YDyAS/Hw5q8N050vG3rf9tgmih1id2COx9ul9rX4Yhv2wz6dgNY+5AA/HN5Pn904Sun+tRmvNtuqY4A+ANsPsSsWH9+Bd9lje/tTINuX7MUENFfxGd1Be5U/vjXn6X5rP/XvEuiyZLcAJkCgvWYTokDbo0+xb/04KJUiV3Ptbe3xQUqPDhYSEG+Bbh/7LPUf62JAFLgMRvdRe5z1fbzvPm8727us9e+S8Zw7To7+SubVK4fphf39tP/iSw21TX/ilZffTF386dZJS/Uvxjr2R7A/Tz+T/qPBBMyqGuGn4nsPwADJrUvAKiOgmSYzbnUC9lYYAb5mbHQCouDIuz/+1gZIymY/BtSXgHWTejP8/eRpKlHi4pmJlM1+POBbr7/T8PKlD9rS2yL9Y5v33v24IX3dR22fjHbqzcAzH0cAhZtxBDhYihAVRNyP4iLt9+H7nzZ025jAEmsJjT7Um4HiIjn0S3M2ClfwUTQToH0LHJoAJjD21ZUA+1FvBp75VUYARZcSoLI0AizeXFsCOPfHXgMoxoIcYGmfVKBMgBPFx/CMfBUHO/Vm4JkfOwJ4ljmMbY/10UY726fbs7XEwZV6yQTATr0ZJKZECeXcj9cA+0XxkRwBtNcSlCVA7yB+nr+HKJZMAOzUm4FnN5LCSxdBirKYkkD62aczAYdfz1aT39RLJgB26s2QdaAV1dH1lO5+lc2n0pyjoCisbwTYr5QE16df9BLmWr1k/LBTb4ZLb19OYkxAWxeEv/raGwu0D0fH1EwPvk3p4Y16yQTATr0ZLISkYNJ+mgauW2Y77pOyca2fkQlY9dlghwnhhQnrNxq6t7NuGUThW5UEJ0BzkLYx6EtA7H/VY02CuArU/qpB9SVg47FqAgTfy1m/UeAzQHwWoK8RnwVoWxYxUWtNGpe/kfQ1hviMgVeC3vdKUNtcOUbyMVj006X57CgbjNIZjwmIzweTJ4DvAeL7APoastmPtmUgcUPqzgSc++d1DTg38D1AfB9AX0M2+9G2ww4XAH4cZv0OFcQ1Qdz2cz3ruYYo1XddgzYaeosT7yZ78w+qDcd+XRa37gVHVwJO2YmNSsAy9/kLkQDP210CFoUUwbe4Ylwp1igf+VLwWDKeSTDmFugrd6QE8tmClI98KUj0e4Qh+4xnEgw9g/KleHFo+1IC4sfUPp5ZAiioRvly+Iv0q7E0Bfq+JJlxRJD0rVHHovbRoChxihHAYMkxCZi/T/hktv3RsAQoQM5ZUj7ypXhxaHv5Zl92+C2yh4x9Egw9g/Kl+LEjIEsAv//3lIx9ElhEF+UjX85/XwPoT8pHvlkC+P2/p2TsawfFj70IZgng9/+ekvGsHZyTDfXfAv3HQKs3Cuwjv//3lIxnEmghpHcCrC/Bj7wxAe3/C0ICap/fswTw+39PyXjWDgshKZisJgBr/z4ynrH4Hx2ATnImNS+cAAAAAElFTkSuQmCC",
    "宿傩": "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",
}

MI = "https://www.myinstants.com/media/sounds/"
# out name: (source file, start s, duration s or None, fade-out s, note)
# 2026-09-29 第三轮：英语配音与不合适的音效已由 tools/build_jjk_audio.py（日语原声 + 动画/Mixkit 音效）替换，
# 这里只保留仍在使用的原始片段（全部为日语或无人声）；本脚本末尾会调用 build_jjk_audio 生成其余音效。
SOUNDS_R3_REPLACED = ("black_flash", "gojo_blue", "gojo_purple_sfx", "gojo_teleport", "sukuna_intro", "sukuna_dismantle",
                      "sukuna_cleave", "sukuna_fuga", "sukuna_world_slash", "mahoraga_summon", "mahoraga_roar",
                      "agito_roar", "agito_thunder")
SOUNDS = {
    "black_flash": ("black-flash-sfx.mp3", 0.0, None, 0.3, "黑闪命中"),
    "gojo_intro": ("throughout-heaven-and-earth-i-alone-am-honored.mp3", 0.0, None, 0.3, "五条悟开场：天上天下唯我独尊"),
    "gojo_blue": ("gojo-lapse-blue.mp3", 8.5, None, 0.3, "术式顺转·苍（截取尾段）"),
    "gojo_red": ("gojo-reversal-red.mp3", 5.8, None, 0.3, "术式反转·赫（截取尾段）"),
    "gojo_purple": ("hollow-purple.mp3", 0.0, 6.5, 0.6, "虚式·茈 语音"),
    "gojo_purple_sfx": ("hollow-purple-no-voice.mp3", 0.0, None, 0.4, "茈 发射音效（无人声）"),
    "gojo_purple_200": ("gojo-200-hollow-purple.mp3", 11.5, None, 0.6, "200%茈（截取后段）"),
    "gojo_domain": ("domain-expansion-gojo.mp3", 0.0, None, 0.5, "领域展开·无量空处"),
    "gojo_teleport": ("teleport-anime.mp3", 0.0, None, 0.1, "瞬移"),
    "sukuna_intro": ("sukuna-laugh.mp3", 0.0, None, 0.3, "宿傩笑声"),
    "sukuna_dismantle": ("dismantle-1_df0eIyY.mp3", 0.0, None, 0.1, "解"),
    "sukuna_cleave": ("sword-slash-1.mp3", 0.0, None, 0.05, "捌"),
    "sukuna_fuga": ("ryomen-sukuna-fuga.mp3", 0.0, None, 0.1, "开（fuga）"),
    "sukuna_domain": ("malevolent-shrine.mp3", 0.0, None, 0.5, "领域展开·伏魔御厨子"),
    "sukuna_world_slash": ("world-cutting-slash.mp3", 0.0, 9.0, 0.8, "世界斩咏唱+斩击"),
    "mahoraga_wheel": ("mahoraga-devine-wheel-adapting-sound.mp3", 0.0, None, 0.2, "法阵转动（适应）"),
    "mahoraga_summon": ("mahoraga-summon.mp3", 0.0, 8.0, 0.8, "八握剑异戒神将魔虚罗 召唤"),
    "mahoraga_roar": ("divine-beast-roar.mp3", 0.0, 3.0, 0.6, "魔虚罗咆哮"),
    "agito_roar": ("big-monster-roar.mp3", 0.0, 2.5, 0.5, "嵌合暗兽咆哮"),
    "agito_thunder": ("electric-shock.mp3", 0.0, 1.6, 0.3, "鵺雷击"),
}
for _k in SOUNDS_R3_REPLACED: SOUNDS.pop(_k)


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def face(png_bytes):
    from PIL import Image
    im = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    if im.size[0] != 64 or im.size[1] not in (32, 64):
        raise RuntimeError("unexpected skin size %s" % (im.size,))
    f = im.crop((8, 8, 16, 16))
    f.alpha_composite(im.crop((40, 8, 48, 16)))
    f = f.resize((128, 128), Image.NEAREST)
    out = io.BytesIO()
    f.save(out, "PNG")
    return out.getvalue()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ffmpeg", default="C:/ffmpeg/bin/ffmpeg.exe" if os.name == "nt" else "ffmpeg")
    a = ap.parse_args()
    for d in (IMG_DIR, SND_DIR, RAW_DIR):
        os.makedirs(d, exist_ok=True)
    open(os.path.join(RAW_DIR, ".gdignore"), "w").close()
    record = {"note": "All assets fetched from the public web for the 咒术回战 characters. Anime audio and community skins keep their original owners' rights (Jujutsu Kaisen © Gege Akutami/Shueisha/MAPPA; skins © their uploaders). Local fan-project use only; not cleared for redistribution.",
              "skins": {}, "sounds": {}}
    for key, (page, how, direct, who) in SKINS.items():
        if how == "mc_skins_embedded":
            try:
                html = fetch(page).decode("utf8", "replace")
                m = re.search(r'data-skin-target="skin"[\s\S]{0,400}?data-skin="data:image/png;base64,([A-Za-z0-9+/=]+)"', html)
                if not m:
                    raise RuntimeError("skin not found on " + page)
                raw = base64.b64decode(m.group(1))
                src = page + " (data-skin embedded PNG, live fetch)"
            except Exception as error:
                if key not in FALLBACK_SKIN_B64:
                    raise
                raw = base64.b64decode(FALLBACK_SKIN_B64[key])
                src = page + " (data-skin embedded PNG; live fetch failed here: %s; bytes fetched from the same page by agent sandbox 2026-09-28)" % error
        else:
            raw = fetch(direct)
            src = direct
        raw_path = os.path.join(RAW_DIR, "skin_%s.png" % key)
        open(raw_path, "wb").write(raw)
        out = face(raw)
        out_path = os.path.join(IMG_DIR, "%s_face.png" % key)
        open(out_path, "wb").write(out)
        record["skins"][key] = {"page": page, "download": src, "credit": who, "raw": raw_path.replace("\\", "/"),
                                "raw_sha256": sha(raw), "output": out_path.replace("\\", "/"), "output_sha256": sha(out),
                                "derivation": "face 8x8 + hat overlay composite, nearest x16 -> 128x128"}
        print("skin", key, sha(raw)[:12])
    for key, (fname, start, dur, fade, note) in SOUNDS.items():
        raw = fetch(MI + fname)
        raw_path = os.path.join(RAW_DIR, fname)
        open(raw_path, "wb").write(raw)
        out_path = os.path.join(SND_DIR, key + ".ogg")
        probe = subprocess.run([a.ffmpeg, "-hide_banner", "-i", raw_path], capture_output=True, text=True, errors="replace").stderr
        m = re.search(r"Duration: (\d+):(\d+):([\d.]+)", probe)
        total = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3)) if m else 0.0
        length = (total - start) if dur is None else min(dur, total - start)
        af = "afade=t=in:d=0.02,afade=t=out:st=%.3f:d=%.3f,loudnorm=I=-16:TP=-1.5:LRA=11" % (max(0.0, length - fade), fade)
        cmd = [a.ffmpeg, "-y", "-hide_banner", "-loglevel", "error", "-ss", "%.3f" % start, "-t", "%.3f" % length, "-i", raw_path,
               "-af", af, "-ar", "44100", "-ac", "2", "-c:a", "libvorbis", "-q:a", "5", out_path]
        subprocess.run(cmd, check=True)
        data = open(out_path, "rb").read()
        record["sounds"][key] = {"page": "https://www.myinstants.com/en/search/?name=" + fname[:-4], "download": MI + fname,
                                 "raw": raw_path.replace("\\", "/"), "raw_sha256": sha(raw), "raw_seconds": round(total, 3),
                                 "trim_start": start, "trim_seconds": round(length, 3), "fade_out": fade,
                                 "filters": af, "output": out_path.replace("\\", "/"), "output_sha256": sha(data), "use": note}
        print("sound", key, round(length, 2), "s")
    for d in (IMG_DIR, SND_DIR):
        json.dump(record, open(os.path.join(d, "SOURCE.json"), "w", encoding="utf8"), ensure_ascii=False, indent=1)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import build_jjk_audio
    build_jjk_audio.main(["--ffmpeg", a.ffmpeg, "--fetch"])
    print("OK", len(record["skins"]), "skins", len(record["sounds"]), "sounds")


if __name__ == "__main__":
    main()
