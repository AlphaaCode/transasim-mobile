#!/usr/bin/env bash
# Cut the phone segments and the logo sting for one composition.
#   bash cut_segments.sh      -> Arabic footage  -> composition/
#   bash cut_segments.sh en   -> English footage -> composition-en/
# Clips are VFR (screenrecord only emits changed frames), so each is made CFR
# first (fps=30 duplicates the held frames), then trimmed. tpad clones the
# last frame where a segment outlives its source.
set -euo pipefail
W="C:/Users/akaro/Documents/GitHub/transasim-mobile/brag-output/work"
C="$W/clips"
if [ "${1:-ar}" = en ]; then
  OUT="$W/../composition-en/assets/video"; SUF="_en"
else
  OUT="$W/../composition/assets/video"; SUF=""
fi
ENC=(-c:v libx264 -preset medium -crf 12 -pix_fmt yuv420p -g 30 -an -movflags +faststart)
SC="scale=864:1920:flags=lanczos"

# seg name, clip, "start-end[,start-end...]", lead pad, total duration
cut() {
  local name=$1 clip=$2$SUF ranges=$3 lead=$4 dur=$5
  local fc="[0:v]fps=30,split=$(echo "$ranges" | tr ',' '\n' | wc -l)"
  local i=0 labels="" parts=""
  IFS=',' read -ra R <<< "$ranges"
  for r in "${R[@]}"; do labels+="[s$i]"; i=$((i+1)); done
  fc+="$labels;"
  i=0
  for r in "${R[@]}"; do
    local a=${r%-*} b=${r#*-}
    fc+="[s$i]trim=start=$a:end=$b,setpts=PTS-STARTPTS[p$i];"
    parts+="[p$i]"; i=$((i+1))
  done
  fc+="${parts}concat=n=${#R[@]}:v=1:a=0,tpad=start_mode=clone:start_duration=$lead:stop_mode=clone:stop_duration=3,trim=duration=$dur,setpts=PTS-STARTPTS,$SC[v]"
  ffmpeg -v error -y -i "$C/$clip.mp4" -filter_complex "$fc" -map "[v]" -r 30 "${ENC[@]}" "$OUT/$name.mp4"
  printf '%-9s %s\n' "$name" "$(ffprobe -v error -show_entries stream=nb_frames,duration -of csv=p=0 "$OUT/$name.mp4")"
}

# Same choreography in both languages; the ranges differ only by the few
# frames each recording's taps and scrolls landed on.
if [ "$SUF" = _en ]; then
  cut seg_s3  clipA "0.90-2.95,4.25-5.40" 0    3.4
  cut seg_s4a clipB "0.10-1.25"           0    1.1
  cut seg_s4b clipB "3.81-6.11"           0.35 2.65
  cut seg_s5a clipC "0.50-1.70"           0    1.2
  cut seg_s5b clipC "3.37-5.97"           0    2.6
  cut seg_s6a clipD "1.46-3.16"           0    1.65
  cut seg_s6b clipD "6.62-8.77"           0    2.15
else
  cut seg_s3  clipA "1.03-3.08,4.37-5.52" 0    3.4
  cut seg_s4a clipB "0.10-1.25"           0    1.1
  cut seg_s4b clipB "3.70-6.00"           0.35 2.65
  cut seg_s5a clipC "0.50-1.72"           0    1.2
  cut seg_s5b clipC "3.33-5.93"           0    2.6
  cut seg_s6a clipD "1.50-3.20"           0    1.65
  cut seg_s6b clipD "6.66-8.81"           0    2.15
fi

# Logo sting: the client's original animation (1920x1080, 8.1 s) speed-ramped
# into the 2.9 s reveal slot. Its static holds are squeezed hardest, so the
# motion keeps a readable pace: formation x2.5, flight and return x3.2, the
# wordmark reveal x2.2, then the finished lockup holds. Source -> comp times:
# arrow leaves 2.13 -> 2.81, docks 4.5 -> 3.56, lockup complete 6.3 -> 4.23
# (synth.js puts its swooshes and the chime on those). Scaled 1:1 for the
# 1652x930 box it is shown in, so the browser never resamples it.
LOGO="E:/disk f/Work/Sabily/sabily logo animation final.mp4"
RAMP="if(lt(T,0.875),(T-0.25)/2.5,if(lt(T,2.0),0.25+(T-0.875)/5,if(lt(T,4.75),0.475+(T-2.0)/3.2,if(lt(T,5.3),1.334375+(T-4.75)/4,1.471875+(T-5.3)/2.2))))"
ffmpeg -v error -y -i "$LOGO" \
  -filter_complex "[0:v]trim=start=0.25,setpts='($RAMP)/TB',fps=30,tpad=stop_mode=clone:stop_duration=2,trim=duration=2.9,setpts=PTS-STARTPTS,scale=1652:930:flags=lanczos,setsar=1[v]" \
  -map "[v]" -r 30 "${ENC[@]}" "$OUT/seg_intro.mp4"
printf '%-9s %s\n' seg_intro "$(ffprobe -v error -show_entries stream=width,height,nb_frames,duration -of csv=p=0 "$OUT/seg_intro.mp4")"
