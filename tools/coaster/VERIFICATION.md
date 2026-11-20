# Workshop expansion r3

This Mac candidate extends the frozen Workshop r2 candidate. The six editable presets use the Workshop v1 format. The three new ones were generated with the native theme catalog, construction generator, autoScenes, serialization, reimport and TrainSim. Rerunning the expansion recipe produced byte-identical baked geometry and timetables. Each new layout passed the source builder's warning checks after reimport.

| New line | Native seats | Circuit | Peak speed | Largest drop | Inversions | Lap |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Crystal Mine | Sit | 817 m | 80.5 km/h | 21.8 m | 0 | 62.7 s |
| Neon Wings | Wing | 1,318 m | 126.2 km/h | 47.8 m | 1 | 64.2 s |
| Phantom Castle | Invert | 967 m | 93.3 km/h | 30.7 m | 2 | 64.5 s |

Each of the six lines has less than 30% shallow track by arc length at absolute pitch below eight degrees. The source programs, models and textures are local authoring inputs. Original Godot geometry renders the components and scenery. The two new seating arrangements use the Workshop lead-eye offsets of (-2.25, 1.38, -0.07) and (-0.32, -1.24, -0.07) metres. The avatar uses the Lantern Lane rig and ride animation.

The Chinese graphical tour on an M1 Pro Mac uses scripted touch, click and controller events through the normal interface. It rides from town, picks from six cards, boards all six, tests platform boarding, switches cameras on the fastest line, checks the seat and eye inside each new themed section, and returns to town. The separate headless Nintendo-layout controller tour exercises all six quick-boarding choices. These are gameplay checks, not physical controller or mobile-device tests. The wheel contact probe sampled 115,560 wheel poses with a worst tread-to-rail discrepancy of 3.10 mm. See evidence/ for player-camera PNGs and logs. The source manifests, presets and baked JSON are included alongside the playable game.

Run the Godot tour in the isolated play copy with --resolution 1080x810 --fixed-fps 20 -- --driver=res://tests/coaster_tour.gd --marks=6.6,10.3,14.4 --timeout=900 --park-locale=zh-CN --shots=/absolute/output --tag=mac. For the TV run use --headless --fixed-fps 30 and add --tv --pad-layout=nintendo --no-shots --window=1920x1080 after the separator. Run python3 tools/coaster/check_tracks.py to verify all six track frames, seams, timelines, seat types and scenery labels.


The final Mac run passed 65 checks and saved 16 original player-camera images. The controller run passed 48 checks. Both confirmed the child's fixed seat transform during the wing and suspended trains' inversions. The project-wide test runner stopped with the three previously recorded web-city bridge failures. An independent bridge run reproduced the same assertions. The park and its input path do not use that bridge.
