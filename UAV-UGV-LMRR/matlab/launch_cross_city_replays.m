function viewers = launch_cross_city_replays(varargin)
%LAUNCH_CROSS_CITY_REPLAYS Open viewers for both frozen city scenes.
% Optional viewer settings are forwarded, for example:
% launch_cross_city_replays('FigurePosition',[50 50 1920 1080])

repoRoot=fileparts(fileparts(mfilename('fullpath')));
cities={'lower_manhattan','chicago'};
viewers=cell(numel(cities),1);
for k=1:numel(cities)
    scenePath=fullfile(repoRoot,'outputs','cross_city_matlab_replay_v3',cities{k},'scene.json');
    assert(isfile(scenePath),'Missing frozen scene: %s',scenePath);
    viewers{k}=open_cross_city_replay_viewer(scenePath,'Visible','on','AutoPlay',false,varargin{:});
end
end
