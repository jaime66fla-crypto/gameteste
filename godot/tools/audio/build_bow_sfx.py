"""Original recurve-bow foley synthesis, no external samples or dependencies.
Offline rendering: fibre stick/slip + wood modes + damped string excitation.
"""
from pathlib import Path
import math, random, struct, wave
RATE=44100
OUT=Path(__file__).resolve().parents[2]/'assets/audio/bow'
OUT.mkdir(parents=True,exist_ok=True)

def noise(n, seed):
    rng=random.Random(seed)
    return [rng.uniform(-1,1) for _ in range(n)]

def lowpass(values,hz):
    a=1-math.exp(-2*math.pi*hz/RATE)
    v=0.
    result=[]
    for x in values:
        v+=a*(x-v)
        result.append(v)
    return result

def band(values,lo,hi):
    high=lowpass(values,hi)
    low=lowpass(values,lo)
    return [a-b for a,b in zip(high,low)]

def write(name, data):
    # Taper every edge and remove DC before peak-normalizing to -2.2 dBFS.
    mean=sum(data)/len(data)
    n=len(data)
    data=[(x-mean)*min(1.,i/(RATE*.004),(n-1-i)/(RATE*.035)) for i,x in enumerate(data)]
    peak=max(abs(x) for x in data) or 1
    data=[x*.78/peak for x in data]
    assert max(abs(x) for x in data)<.79
    payload=struct.pack('<'+'h'*n,*(round(x*32767) for x in data))
    with wave.open(str(OUT/name),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(payload)
    rms=math.sqrt(sum(x*x for x in data)/n)
    print(name,'duration',round(n/RATE,3),'peak',round(max(abs(x) for x in data),3),'rms',round(rms,4))

def draw(variant):
    n=int(.94*RATE)
    rng=random.Random(1001+variant*127)
    raw=noise(n,710+variant)
    fibre=band(raw,550,6100)
    grain=band(raw,90,1200)
    out=[0.]*n
    # Sustained but irregular braided-fibre drag, growing under tension.
    for i in range(n):
        t=i/RATE
        envelope=math.sin(math.pi*min(t/.94,1))**.55
        texture=.65+.22*math.sin(2*math.pi*31*t)+.12*math.sin(2*math.pi*67*t)
        out[i]=envelope*texture*(fibre[i]*.10+grain[i]*.08)
    # Short non-musical stick/slip creaks: wood, serving wrap and fibre grains.
    at=.015
    while at<.88:
        duration=rng.uniform(.009,.037)
        freq=rng.uniform(170,460)*(1+at*.55)
        phase=rng.random()*math.tau
        gain=rng.uniform(.035,.10)*(0.55+at*.6)
        start=int(at*RATE)
        for j in range(int(duration*RATE)):
            i=start+j
            if i>=n:break
            t=j/RATE
            u=t/duration
            phase+=math.tau*freq*(1+.16*math.sin(math.pi*u))/RATE
            slip=math.sin(math.pi*u)**2
            out[i]+=slip*gain*(math.sin(phase)+.21*math.sin(phase*2.17)+fibre[i]*1.1)
        at+=rng.uniform(.019,.052)
    return out

def release(variant):
    # Revision 2: a dry serving slap and limb knock, no swept/tonal "pew".
    n=int(.48*RATE)
    rng=random.Random(751+variant*59)
    raw=noise(n,3081+variant)
    serving=band(raw,1100,8500)
    body=band(noise(n,5201+variant),65,1250)
    air=band(noise(n,6301+variant),1600,6800)
    # A very short noisy waveguide adds cord texture without a sustained note.
    lag=round(RATE/rng.uniform(270,340))
    delay=noise(lag,711+variant)
    string=[]
    for i in range(n):
        j=i%lag
        sample=delay[j]
        delay[j]=.57*(delay[j]+delay[(j+1)%lag])*.5
        string.append(sample)
    out=[]
    for i in range(n):
        t=i/RATE
        snap=serving[i]*.85*math.exp(-t/.0035)
        # Broad, non-musical wood contact; tight rather than bass-heavy.
        knock=body[i]*1.4*math.exp(-t/.013)
        cord=string[i]*.22*math.exp(-t/.020)
        second_tap=serving[i]*.18*math.exp(-(t-.006)/.003) if t>=.006 else 0.
        flight_t=t-.010
        flight=air[i]*.13*(1-math.exp(-flight_t/.004))*math.exp(-flight_t/.028) if flight_t>0 else 0.
        out.append(snap+knock+cord+second_tap+flight)
    return out

if __name__ == '__main__':
    import sys
    for variant in range(3):
        if '--release-only' not in sys.argv:
            write(f'bow_draw_{variant}.wav',draw(variant))
        write(f'bow_release_{variant}.wav',release(variant))
