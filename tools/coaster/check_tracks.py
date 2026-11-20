"""Validate the baked builder frames and native TrainSim timelines using only Python."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
dot = lambda a, b: sum(x*y for x, y in zip(a, b))
def angle(a, b):
    return math.acos(max(-1, min(1, dot(a, b))))

def check(file):
    data = json.loads(file.read_bytes())
    save = json.loads((ROOT/'tools/coaster/presets'/file.name).read_bytes())
    frames, schedule, ds = data['frames'], data['timeline'], data['ds']
    length = len(frames)*ds
    assert save['v'] == 1 and save['mode'] == 'pro' and len(save['track']['nodes']) >= 4
    assert all(len(n) == 7 for n in save['track']['nodes'])
    assert data['station']['len'] >= 6 and data['halfWidth'] == save['track']['opts']['halfWidth']
    if "seat" in data:
        assert len(data["scenes"]) == len(frames) and any(data["scenes"])
        assert data["seat"] == save["train"]["seat"]
        assert any(node[6] for node in save["track"]["nodes"])
        assert len(data["eye"]) == 3 and all(math.isfinite(c) for c in data["eye"])
        if data["seat"] == "invert":
            assert data["eye"][1] < 0 and save["track"]["opts"]["hang"]
        if data["seat"] == "wing":
            assert abs(data["eye"][0]) > 2 and data["halfWidth"] == 2.9
    max_roll_step = 0
    winding = largest_turn = 0
    for i,row in enumerate(frames):
        nxt = frames[(i+1)%len(frames)]
        assert len(row) == 10 and all(math.isfinite(x) for x in row)
        tangent,up = row[3:6],row[6:9]
        assert abs(dot(tangent,up)) < 1e-4
        assert abs(dot(tangent,tangent)-1) < 1e-4 and abs(dot(up,up)-1) < 1e-4
        assert math.dist(row[:3],nxt[:3]) < ds*1.1
        max_roll_step=max(max_roll_step,angle(up,nxt[6:9]))
        theta=math.atan2(nxt[3],nxt[5])-math.atan2(row[3],row[5])
        delta=math.atan2(math.sin(theta),math.cos(theta))
        if delta*winding < 0 and abs(delta)>0.0005: winding=0
        winding+=delta
        largest_turn=max(largest_turn,abs(winding))
    assert math.degrees(max_roll_step) < 8
    if file.stem == 'copper-coil': assert largest_turn>math.pi*2.6
    assert all(v>=0 for _,v in schedule)
    assert schedule[0][1]==schedule[-1][1]==0
    assert abs(schedule[0][0]-data['stop'])<1e-5 and schedule[-1][0]==data['stop']
    travelled=sum((b[0]-a[0]+length/2)%length-length/2 for a,b in zip(schedule,schedule[1:]))
    assert abs(travelled-length)<0.01
    shallow_fraction=sum(abs(row[4]) < math.sin(math.radians(8)) for row in frames)/len(frames)
    assert shallow_fraction < 0.30, (file.stem, shallow_fraction)
    return dict(shallow_fraction=shallow_fraction, line=file.stem,frames=len(frames),nodes=len(save['track']['nodes']),
                length_m=length,peak_kmh=max(v for _,v in schedule)*3.6,lap_s=(len(schedule)-1)/20,
                max_frame_up_step_deg=math.degrees(max_roll_step),longest_turn_deg=math.degrees(largest_turn),
                full_lap_error_m=abs(travelled-length))
if __name__ == '__main__':
    print(json.dumps([check(f) for f in sorted((ROOT/'game/coasters').glob('*.json'))],indent=2))
