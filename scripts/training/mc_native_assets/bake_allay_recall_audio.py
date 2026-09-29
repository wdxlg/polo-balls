import wave,struct,math,random,os
root='audio/characters/我的世界/allay';os.makedirs(root,exist_ok=True)
rate=24000
for name,dur in [('spin',.7),('release',.4)]:
 rng=random.Random(741);samples=[];smooth=0.
 for i in range(int(rate*dur)):
  t=i/rate;value=0.
  if name=='spin':
   for k,onset in enumerate([0,.17,.31,.43,.53,.61]):
    a=t-onset
    if a>=0:
     f=[784,988,1175,1568,1976,2350][k]
     env=(1-math.exp(-a*450))*math.exp(-a*25)
     value+=.25*env*(math.sin(2*math.pi*f*a)+.22*math.sin(2*math.pi*f*2*a))
   smooth=.88*smooth+.12*rng.uniform(-1,1)
   value+=smooth*.13*(t/dur)*math.sin(math.pi*t/dur)
  else:
   env=(1-math.exp(-t*500))*math.exp(-t*17)
   smooth=.70*smooth+.30*rng.uniform(-1,1)
   value=.60*smooth*env
   for f in [523.25,784,1046.5]: value+=.115*env*math.sin(2*math.pi*f*t)
  value*=min(1,(dur-t)/.025)
  samples.append(int(max(-.95,min(.95,value))*32767))
 with wave.open(root+'/recall_'+name+'.wav','wb') as w:w.setparams((1,2,rate,0,'NONE','not compressed'));w.writeframes(struct.pack('<%dh'%len(samples),*samples))
print('Recall phase WAV assets generated')
