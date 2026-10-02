import sys, numpy as np, wave
w=wave.open(sys.argv[1]); sr=w.getframerate(); n=w.getnframes()
x=np.frombuffer(w.readframes(n),dtype=np.int16).reshape(-1,2).astype(np.float32).mean(axis=1)/32768
def bands(t0,t1):
    seg=x[int(t0*sr):int(t1*sr)]; seg=seg*np.hanning(len(seg))
    S=np.abs(np.fft.rfft(seg))**2; f=np.fft.rfftfreq(len(seg),1/sr)
    out=[10*np.log10(S[(f>=lo)&(f<hi)].sum()+1e-12) for lo,hi in [(20,60),(60,120),(120,250),(250,500),(500,1000),(1000,2000),(2000,4000),(4000,8000),(8000,16000)]]
    ref=max(out); return ' '.join(f'{v-ref:6.1f}' for v in out)
print('bands:     20-60  60-120 120-250 250-500 .5-1k   1-2k   2-4k   4-8k   8-16k')
for t0,t1,name in [(0.0,1.0,'pickup'),(1.0,2.5,'hook'),(3.0,4.8,'break'),(6.0,8.0,'groove'),(17.0,19.0,'outro'),(19.0,21.0,'end')]:
    print(f'{name:7s} {bands(t0,t1)}')
