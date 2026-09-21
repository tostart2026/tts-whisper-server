#!/bin/bash
# 支持的语言代码 (Whisper 支持 99 种语言):
# zh (中文), en (英语), ja (日语), ko (韩语), fr (法语), de (德语), es (西班牙语)
# ru (俄语), ar (阿拉伯语), pt (葡萄牙语), it (意大利语), tr (土耳其语)
# vi (越南语), th (泰语), pl (波兰语), nl (荷兰语), id (印尼语)
# sv (瑞典语), fi (芬兰语), da (丹麦语), no (挪威语), cs (捷克语)
# hu (匈牙利语), ro (罗马尼亚语), uk (乌克兰语), el (希腊语), he (希伯来语)
# hi (印地语), bn (孟加拉语), ta (泰米尔语), te (泰卢固语), mr (马拉地语)
# 完整列表请参考: https://github.com/openai/whisper/blob/main/whisper/tokenizer.py

LANG="${1:-en}"  # 默认英语，可传参指定如: ./test2.sh zh

# 所有支持的语言码 (99种) - 直接从 Whisper tokenizer.py 提取
ALL_LANGUAGES="zh en ja ko fr de es ru ar pt it vi th pl nl id sv fi da no hu ro uk el hi bn ta te ml ms ca lv sa si am ug ur eu ku lo kw hy ne mn bs kk sq sw gl pa km sn yo so af oc ka be tg sd gu yi tt haw ln ha ba jw su yue hr bg lt la mi cy sk fa uz fo ht ps tk nn mt my bo tl mg as"

# 语言码到中文名称的映射 (99种语言)
declare -A LANG_NAMES
LANG_NAMES[zh]="中文"
LANG_NAMES[en]="英语"
LANG_NAMES[ja]="日语"
LANG_NAMES[ko]="韩语"
LANG_NAMES[fr]="法语"
LANG_NAMES[de]="德语"
LANG_NAMES[es]="西班牙语"
LANG_NAMES[ru]="俄语"
LANG_NAMES[ar]="阿拉伯语"
LANG_NAMES[pt]="葡萄牙语"
LANG_NAMES[it]="意大利语"
LANG_NAMES[vi]="越南语"
LANG_NAMES[th]="泰语"
LANG_NAMES[pl]="波兰语"
LANG_NAMES[nl]="荷兰语"
LANG_NAMES[id]="印尼语"
LANG_NAMES[sv]="瑞典语"
LANG_NAMES[fi]="芬兰语"
LANG_NAMES[da]="丹麦语"
LANG_NAMES[no]="挪威语"
LANG_NAMES[cs]="捷克语"
LANG_NAMES[hu]="匈牙利语"
LANG_NAMES[ro]="罗马尼亚语"
LANG_NAMES[uk]="乌克兰语"
LANG_NAMES[el]="希腊语"
LANG_NAMES[hi]="印地语"
LANG_NAMES[bn]="孟加拉语"
LANG_NAMES[ta]="泰米尔语"
LANG_NAMES[te]="泰卢固语"
LANG_NAMES[mr]="马拉地语"
LANG_NAMES[ml]="马拉雅拉姆语"
LANG_NAMES[ca]="加泰罗尼亚语"
LANG_NAMES[lv]="拉脱维亚语"
LANG_NAMES[sa]="梵语"
LANG_NAMES[si]="僧伽罗语"
LANG_NAMES[am]="阿姆哈拉语"
LANG_NAMES[ug]="乌古里语"
LANG_NAMES[ur]="乌尔都语"
LANG_NAMES[eu]="巴斯克语"
LANG_NAMES[ku]="库尔德语"
LANG_NAMES[lo]="老挝语"
LANG_NAMES[kw]="科尼什语"
LANG_NAMES[hy]="亚美尼亚语"
LANG_NAMES[ne]="尼泊尔语"
LANG_NAMES[mn]="蒙古语"
LANG_NAMES[bs]="波斯尼亚语"
LANG_NAMES[kk]="哈萨克语"
LANG_NAMES[sq]="阿尔巴尼亚语"
LANG_NAMES[sw]="斯瓦希里语"
LANG_NAMES[gl]="加利西亚语"
LANG_NAMES[pa]="旁遮普语"
LANG_NAMES[km]="高棉语"
LANG_NAMES[sn]="肖纳语"
LANG_NAMES[yo]="约鲁巴语"
LANG_NAMES[so]="索马里语"
LANG_NAMES[af]="阿弗里卡语"
LANG_NAMES[oc]="奥克语"
LANG_NAMES[ka]="格鲁吉亚语"
LANG_NAMES[be]="白俄罗斯语"
LANG_NAMES[tg]="塔吉克语"
LANG_NAMES[sd]="信德语"
LANG_NAMES[gu]="古吉拉特语"
LANG_NAMES[yi]="意第绪语"
LANG_NAMES[tt]="塔塔尔语"
LANG_NAMES[haw]="夏威夷语"
LANG_NAMES[ln]="林加拉语"
LANG_NAMES[ha]="豪萨语"
LANG_NAMES[ba]="巴什基尔语"
LANG_NAMES[jw]="爪哇语"
LANG_NAMES[su]="巽他语"
LANG_NAMES[yue]="粤语"
LANG_NAMES[hr]="克罗地亚语"
LANG_NAMES[bg]="保加利亚语"
LANG_NAMES[lt]="立陶宛语"
LANG_NAMES[la]="拉丁语"
LANG_NAMES[mi]="毛利语"
LANG_NAMES[cy]="威尔士语"
LANG_NAMES[sk]="斯洛伐克语"
LANG_NAMES[fa]="波斯语"
LANG_NAMES[uz]="乌兹别克语"
LANG_NAMES[fo]="法罗语"
LANG_NAMES[ht]="海地克里奥尔语"
LANG_NAMES[ps]="Pashto"
LANG_NAMES[tk]="土库曼语"
LANG_NAMES[nn]="挪威尼诺斯克语"
LANG_NAMES[mt]="马尔代夫语"
LANG_NAMES[my]="缅甸语"
LANG_NAMES[bo]="藏语"
LANG_NAMES[tl]="宿务语"
LANG_NAMES[mg]="马达加斯加语"
LANG_NAMES[as]="阿萨姆语"

CODES=($ALL_LANGUAGES)

if echo "$ALL_LANGUAGES" | grep -qw "$LANG"; then
  curl -X POST "http://localhost:8000/v1/audio/transcriptions" \
    -F "file=@./关税.wav" \
    -F "model_name=whisper-1" \
    -F "language=$LANG" \
    -F "response_format=json"
else
  echo "错误: 不支持的语言码 '$LANG'"
  echo "支持的语言码列表 (共 99 种):"
  for i in "${!CODES[@]}"; do
    code="${CODES[$i]}"
    name="${LANG_NAMES[$code]:-Unknown}"
    printf "  %s (%s)" "$code" "$name"
    if (( (i + 1) % 5 == 0 )) || (( i == ${#CODES[@]} - 1 )); then
      echo ""
    else
      echo -n " "
    fi
  done
  exit 1
fi