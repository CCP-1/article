# UAV–UGV cooperative rescue: urban data and animated replays

Supporting materials for the two archived cases in the manuscript section on cooperative rescue in three-dimensional urban scenes.

## Animated cases

| City | Full animation | Frozen replay scene | Terminal status |
|---|---|---|---|
| Lower Manhattan | [MP4 video](outputs/cross_city_matlab_replay_v3/lower_manhattan/replay.mp4) | [scene.json](outputs/cross_city_matlab_replay_v3/lower_manhattan/scene.json) | [PNG](outputs/cross_city_matlab_replay_v3/lower_manhattan/final_status.png) |
| Chicago | [MP4 video](outputs/cross_city_matlab_replay_v3/chicago/replay.mp4) | [scene.json](outputs/cross_city_matlab_replay_v3/chicago/scene.json) | [PNG](outputs/cross_city_matlab_replay_v3/chicago/final_status.png) |

Download the MP4 files to play the complete animations. The frozen scenes contain roads, buildings, resources, tasks, search regions, committed routes, events and status timelines. Both demonstrations use layout 1, world seed 81001 and a 95 min horizon; Lower Manhattan uses policy 3 and Chicago policy 2. These are simulation demonstrations, not records of real incidents.

## Urban geometry

- [Lower Manhattan](data/lower_manhattan/environment/): OSM-derived building polygons and the largest-component vehicle road network, in GeoJSON.
- [Chicago](data/chicago_official_v1/): archived municipal road-network input and airspace/building geometry used by the replay. The frozen Chicago scene also includes its building polygons and road geometry in local coordinates.

The two cities have different source datasets. Lower Manhattan is OSM-derived; Chicago uses municipal open geometry. These are processed simulation inputs rather than raw `.osm` extracts. Coordinates and projection origins are recorded in each frozen scene.

## Interactive playback

Download this directory while preserving its structure. In MATLAB R2022a or later, run:

```matlab
addpath('matlab');
viewers = launch_cross_city_replays;
```

The viewer provides playback, a time slider, event navigation, camera controls and layer switches. It reads the archived scenes without retraining a policy or rerunning optimization. The other MATLAB utilities support individual-city viewing and rendering.

## Attribution and file integrity

Lower Manhattan geometry is derived from © OpenStreetMap contributors; see [OpenStreetMap copyright and data licensing](https://www.openstreetmap.org/copyright). Chicago geometry is derived from City of Chicago municipal open data archived for this study; see the [Chicago Data Portal](https://data.cityofchicago.org/). Original source-data terms continue to apply.

`FILES.json` records byte sizes and SHA-256 checksums. This folder provides the two case studies, their geometry and playback materials; it is not a release of the complete training or 360-instance evaluation pipeline.
