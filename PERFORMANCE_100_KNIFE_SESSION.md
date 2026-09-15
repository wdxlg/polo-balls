# 100 灏忓垁鐚?/ 50脳50锛氭湰杞紭鍖栦笌楠岃瘉

## 缁撹锛氭湁鎵€鏀瑰杽锛屽皻鏈В鍐虫祦鐣呮€ч棶棰?
鍦ㄥ綋鍓?ShunCode 宸ヤ綔鍖?`E:\godot\polo-balls` 淇敼骞跺疄娴嬨€備娇鐢ㄧ敤鎴锋寚瀹氱殑 Steam Godot 4.7.2锛屽彲瑙嗙獥鍙?540脳960锛孎orward+ / D3D12 / RTX 4060 Laptop GPU銆?
鏈疆姝ｅ紡閫昏緫宸叉帴鍏ヤ笁椤逛紭鍖栵紱褰撳墠鍘嬪姏鍦烘櫙浠嶄粎绾?5 FPS锛屼笉鑳借涓衡€滅櫨浜烘祦鐣呪€濋獙鏀堕€氳繃銆?
| 鎸囨爣 | 鏈疆寮€濮嬪墠 session_baseline | 鏈€缁堜唬鐮?session_verified |
|---|---:|---:|
| 骞冲潎 FPS | 3.870 | 5.308 |
| 甯ц€楁椂 P50 | 216.194 ms | 167.776 ms |
| 甯ц€楁椂 P95 | 407.823 ms | 298.049 ms |
| 甯ц€楁椂鏈€澶у€?| 485.148 ms | 328.016 ms |
| 閲囨牱甯ф暟 | 47 | 64 |
| 閲囨牱澧欓挓鏃堕暱 | 12.146 s | 12.057 s |
| 鏈€灏戝瓨娲昏鑹?| 92 | 88 |
| 鑺傜偣宄板€?| 10106 | 8740 |
| 鍒涘缓 100 浜鸿€楁椂 | 160.158 ms | 221.682 ms |

鏈€缁堝抚鐜囨瘮鏈疆鍩虹嚎楂樼害 37%锛屼絾涓ゆ鎴樻枟鍏佽鑷劧姝讳骸锛屾ā鎷熸帹杩涘拰瀛樻椿浜烘暟涓嶅悓锛屼笉鏄弗鏍煎悓鐘舵€佸洖鏀炬垨鍏ㄧ▼鍥哄畾 100 浜虹殑绋虫€佸鐓с€傚垵濮嬪寲鍙樻參涓昏鍖呭惈鏂板闊抽棰勭儹鎴愭湰锛涙病鏈夋妸杩欓儴鍒嗗紑閿€闅愮瀿鍦ㄦ垬鏂楁寚鏍囦腑銆傚彟涓€杞帴杩戞渶缁堢増鏈殑杩愯寰楀埌 5.462 FPS锛屼笉搴旀嵁姝ゆ壙璇虹ǔ瀹氬抚鐜囥€?
鍦烘櫙锛?00 涓皬鍒€鐚庯紝涓ら槦鍚?50 浜猴紝Map50x50锛屽弸浼ゅ叧闂紝琛€娑叉晥鏋滃紑鍚紝姝ｅ父鐢熷懡銆佹敾鍑诲拰姝讳骸锛? 鍊嶉€燂紝鍏抽棴 VSync銆傛病鏈夊噺灏戜汉鏁般€佷激瀹炽€侀鍒€銆佹畫褰辨暟閲忥紝涔熸病鏈夐檷浣庣墿鐞嗘洿鏂伴鐜囨垨寮€鍚嫭绔嬫覆鏌撶嚎绋嬨€?
## 鏈疆鐢熶骇鏀瑰姩

1. `scripts/shooter/knife.gd`
   - 鏅€氶鍒€鍦ㄧ墿鐞嗘洿鏂版湡闂翠娇鐢ㄧ幇鏈?`classes/after_image_render_batch.gd` 绠＄悊娈嬪奖 RID锛岄伩鍏嶆瘡寮犳畫褰卞垱寤?Sprite2D 鍜岀嫭绔?Tween銆?   - 淇濇寔娈嬪奖閲囨牱鏃舵満銆佹暟閲忋€侀€忔槑鎺掑簭鍒嗙粍銆佹寔缁椂闂村拰鏇茬嚎锛涗笉鏀寔鐨勮妭鐐圭壒鎬ц嚜鍔ㄥ洖閫€鍘熷疄鐜般€?   - 闈炵墿鐞嗛樁娈典繚鐣欏師瀹炵幇锛岄伩鍏嶅湪 SceneTree Tween 闃舵涓垱寤烘畫褰辨椂鎻愬墠鎺ㄨ繘涓€甯с€?   - 淇濈暀 `batch_after_image_snapshots` 寮€鍏筹紝鍙湪 Inspector 鍏抽棴浠ュ鐓у師璺緞銆?2. `classes/after_image_render_batch.gd`
   - 灏嗙洿鎺ヨ绠楃殑杩涘害姣斾緥鏀逛负涓庡師瀹炵幇鐩稿悓鐨?`Tween.interpolate_value` 绾挎€?/ EASE_IN_OUT 杩愮畻銆?   - 淇鍒濇瑙嗚瀵圭収鍑虹幇鐨勫皯閲忓崟閫氶亾 1 绾у樊寮傦紱鏈€缁堜弗鏍煎儚绱犳瘮杈冧负闆跺樊寮傦紝娌℃湁鏀惧娴嬭瘯闃堝€笺€?3. `global/audios.gd` 涓?`scripts/characters/鏉€鎴皷濉?灏忓垁鐚?gd`
   - 棣栨鍒涘缓灏忓垁鐚庢椂棰勭儹 `KnifeThrow1` 鐨?128 涓?Ogg playback銆?   - 浣跨敤椤圭洰宸叉湁鐨?`prewarmed_audio_stream.gd`锛涗粎褰?playback 娌℃湁澶栭儴鎸佹湁寮曠敤鏃跺鐢紝蹇欑鐨勫０闊充笉琚姠鍗狅紝瀹归噺涓嶈冻鍥為€€鏂板缓銆?   - 涓嶆敼鍙樻挱鏀捐皟鐢ㄦ鏁般€佸弬鏁般€侀煶楂橀殢鏈哄寲銆佽В鐮佸櫒鍜岄煶棰戞€荤嚎璺敱锛涘叾浠栭煶棰戞牸寮忎笉鎺ュ叆姝や紭鍖栥€?4. `global/game.gd`
   - 杩愯鏃剁炕璇戜娇鐢ㄩ潪鎸佷箙 Control 鍒嗙粍绱㈠紩锛屼笉鍐嶉€掑綊鎵弿鎵€鏈夐鍒€銆佽鏃跺櫒鍜岀壒鏁堣妭鐐广€?   - 淇濈暀鍔ㄦ€佹枃瀛楀埛鏂般€佸綋鍓嶅満鏅笌 Game 鐨勮寖鍥撮檺鍒躲€佸唴閮ㄨ妭鐐规帓闄よ鍒欍€佽妭鐐归€€鍑?/ 閲婃斁 / 閲嶆寕澶勭悊銆?   - 浠嶇劧姣忔鎵弿閲嶆柊寤虹珛缈昏瘧缁撴灉缂撳瓨锛屼笉寮曞叆璺ㄥ抚璇戞枃缂撳瓨銆?
娌℃湁鎺ュ叆 `.performance_tools` 涓殑瀹為獙鍘熺敓 DLL銆佸紓姝ュ満鏅瀯閫犳垨鏇存崲 Godot 鍙墽琛屾枃浠躲€?
## 楠岃瘉

鎵€鏈変笅杩版渶缁堟祴璇曞潎閫氳繃 Start-Process -Wait -PassThru 绛夊緟瀹為檯 Godot 閫€鍑哄苟妫€鏌?ExitCode=0锛岃€岄潪鍙緷璧?PowerShell 鐨勯粯璁ゆ垚鍔熺姸鎬併€?
- 娈嬪奖瑙嗚锛氭甯告簮銆佹彁鍓嶉噴鏀炬簮鍚?7 甯э紝鍏?14 甯т弗鏍奸€愬瓧鑺備竴鑷达紝瑕嗙洊鍏椋庢牸銆佺炕杞€侀鑹层€佸涓綅缃強娣″嚭锛涚敓鍛藉懆鏈熺粨鏉熷悗 snapshots 鍜?groups 鍧囦负绌恒€?- 闊抽锛?85 椤癸紝0 澶辫触锛岃鐩栧鐢ㄣ€佹墦鏂悗閲嶅惎銆乻eek銆佷笉鍚屾挱鏀鹃€熺巼鍙婂閮ㄦ寔鏈夊紩鐢紱杩欐槸 playback 绾ч獙璇侊紝涓嶆槸澶氫汉鑱旀満闊抽鐨勫叏閲忔祴璇曘€?- 鎴樻枟瀛樺湪鎬ф棫濂戠害锛?08 椤癸紝0 澶辫触銆?- 鏂板缈昏瘧绱㈠紩娴嬭瘯锛? 椤癸紝0 澶辫触锛岃鐩栧姩鎬佹柊澧炪€佸唴閮ㄨ妭鐐瑰強鍏跺悗浠ｃ€佺Щ鍏?/ 绉诲嚭鍐呴儴瀛愭爲銆佺Щ鍑?/ 閲嶆寕銆侀噴鏀惧拰鍔ㄦ€佹枃鏈€?- 缈昏瘧寰熀鍑嗭細3000 涓潪 Control 鑺傜偣 + 200 涓?Label锛?0 娆℃壂鎻忥紝鏃ч€掑綊绾?37.180 ms锛岀储寮曠害 13.682 ms銆傛缁撴灉浠呬负灞€閮ㄥ井鍩哄噯锛屼笉绛夊悓鏁村眬鏀剁泭銆?- 鏈€缁堢湡瀹炲鎴樺熀鍑嗘甯搁€€鍑猴紝缂栬緫鍣?diagnostics 鏃犻敊璇?/ 璀﹀憡銆傜┖ diagnostics 涓嶄綔涓虹嫭绔嬬殑瀹屾暣姝ｇ‘鎬ц瘉鏄庛€?
鏈畬鎴愶細鍏ㄨ鑹叉妧鑳姐€佸浜哄悓姝ャ€佸叏灞€鏆傚仠 / 澶氬€嶇巼鎴樻枟銆佷笉鍚屽湴鍥惧拰闀挎椂闂寸ǔ鎬佺殑瀹屾暣鍥炲綊銆?
## 鎺掗櫎鐨勬柟妗?
鏈疆灏濊瘯浠呴€氳繃鍛戒护琛屽惎鐢ㄧ嫭绔嬫覆鏌撶嚎绋嬶細绾?3.976 FPS锛屾敹鐩婁笉鏄庢樉锛孏odot 鎻愮ず璇ュ姛鑳藉疄楠屾€э紝閫€鍑烘椂鎶?render-thread finalize 閿欒銆傛湭鍐欏叆 project.godot锛屾寮忎唬鐮佷粛浣跨敤榛樿瀹夊叏妯″紡銆?
## 鐣欏瓨涓庡鐜?
- `scripts/training/benchmark_session_baseline.json`
- `scripts/training/benchmark_session_verified.json`
- 瀵瑰簲鐨?`benchmark_session_baseline_engine.log`銆乣benchmark_session_verified_engine.log`
- `scripts/training/test_batch_normal_session_verified.log`
- `scripts/training/test_batch_death_session_verified.log`
- `scripts/training/test_audio_pool_session_verified.log`
- `scripts/training/test_performance_contracts_session_verified.log`
- `scripts/training/test_localization_index_session_verified.log`
- 鏂板娴嬭瘯锛歚tests/test_localization_index.gd`
- 娈嬪奖姣旇緝娴嬭瘯鏂板 `--kill-source`锛涘師鐢熷疄楠屽鐓ф祴璇曟樉寮忓叧闂敓浜ф壒閲忚矾寰勶紝閬垮厤瀵圭収鍩虹嚎琚浛鎹€?
```powershell
$g = 'E:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
$p = Start-Process -FilePath $g -ArgumentList @('--path','.', '--resolution','540x960', '--script','res://scripts/training/benchmark_100.gd','--','--label=manual_verify') -NoNewWindow -Wait -PassThru
$p.ExitCode
```

娴嬭瘯鍏ュ彛涓嶆寕鍒版甯告父鎴忓満鏅紱鍩哄噯姝ｅ父缁撴潫浼氭仮澶嶆祴璇曡繘绋嬩腑鐨?Game 璁剧疆銆備笉瑕佸悓鏃惰繍琛屽涓帇鍔涙祴璇曟垨鍦ㄥ彟涓€娓告垙杩涚▼閲屼慨鏀逛繚瀛樿缃€?
## 浠嶉渶缁х画瑙ｅ喅鐨勭摱棰?
鐧句汉鏀诲嚮閾句粛鏈夊ぇ閲忓畬鏁?ball 娲剧敓椋炲垁鍦烘櫙鍒涘缓 / 閲婃斁銆佽剼鏈皟鐢ㄣ€佸彈鍑诲儚绱犻噰鏍峰拰鏁堟灉鐢熷懡鍛ㄦ湡寮€閿€銆傚皬淇笉瓒充互浠?5 FPS 杈惧埌娴佺晠銆備笅涓€闃舵闇€瑕侀拡瀵瑰綋鍓嶆寮忎唬鐮侀噸鏂伴噰闆嗙ǔ瀹氬満鏅?profile锛屽啀璇勪及杞婚噺椋炲垁鐢熷懡鍛ㄦ湡 / 纰版挒鎺ュ彛鎴栨洿娣卞眰鎵瑰鐞嗛噸鏋勶紝骞舵槑纭獙璇佸懡涓€佷激瀹冲綊灞炪€佺壒娈婄姸鎬併€佽仈鏈恒€佹殏鍋滀笌閲嶇疆锛涗笉鑳芥妸鐩墠缁撴灉绉颁负宸茬粡瑙ｅ喅銆?