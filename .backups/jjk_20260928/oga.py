import urllib.request,re,sys
UA={'User-Agent':'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124 Safari/537.36'}
pages=['hit-animation-frame-by-frame','hit-animation-2-frame-by-frame','2d-explosion-animations-frame-by-frame','2d-explosion-animations-2-frame-by-frame','2d-spell-effects','lightning-animation','animated-particle-effects-1','animated-particle-effects-2','lasers-and-beams','animated-blue-ring-explosion','fire-fx-burning-fire-animation','particle-pack-80-sprites','smoke-particle-assets','high-resolution-slash-effects','slash-effect-collection','thunderbolt','explosion-effects-and-more','25-special-effects-rendered-with-blender']
for p in pages:
    try:
        h=urllib.request.urlopen(urllib.request.Request('https://opengameart.org/content/'+p,headers=UA),timeout=30).read().decode('utf8','ignore')
    except Exception as e:
        print(p,'ERR',e); continue
    lic=re.findall(r'<div class="license-name">([^<]+)</div>',h) or re.findall(r'licenses/([a-z\-0-9\.]+)',h)[:3]
    files=re.findall(r'href="(https://opengameart.org/sites/default/files/[^"]+)"[^>]*>([^<]+)</a>\s*<span class="file-size"?>?',h)
    files2=sorted(set(re.findall(r'https://opengameart.org/sites/default/files/(?!styles)[^"\s]+\.(?:zip|png|7z|rar|gif)',h)))
    print('##',p,'|',lic,'|',files2[:8])
