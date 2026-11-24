function manifest = generate_cross_city_replay_v3(outputRoot,varargin)
%GENERATE_CROSS_CITY_REPLAY_V3 Render two-city state-explicit dynamic replays.
% Example high-resolution export:
% generate_cross_city_replay_v3([], 'FigurePosition',[50 50 2560 1440], ...
%     'PngResolution',600,'FrameRate',20,'VideoQuality',100)

repoRoot=fileparts(fileparts(mfilename('fullpath')));
if nargin<1||isempty(outputRoot)
    outputRoot=fullfile(repoRoot,'outputs','cross_city_matlab_replay_v3');
end
assert(isfolder(outputRoot),'Missing upgraded replay root: %s',outputRoot);
cities={'lower_manhattan','chicago'};
audits=cell(numel(cities),1);
for k=1:numel(cities)
    scenePath=fullfile(outputRoot,cities{k},'scene.json');
    outDir=fullfile(outputRoot,cities{k});
    assert(isfile(scenePath),'Missing upgraded scene: %s',scenePath);
    audits{k}=render_cross_city_replay(scenePath,outDir,varargin{:});
end
manifest=struct('status','passed','viewer_version','3.0', ...
    'generated_at',char(datetime('now','TimeZone','Asia/Shanghai')), ...
    'source_artifact','cross_city_matlab_replay_v1_frozen_state_upgrade', ...
    'cities',{cities},'audits',{audits});
fid=fopen(fullfile(outputRoot,'artifact_manifest.json'),'w');assert(fid>=0);
fprintf(fid,'%s',jsonencode(manifest,'PrettyPrint',true));fclose(fid);
disp(manifest);
end
