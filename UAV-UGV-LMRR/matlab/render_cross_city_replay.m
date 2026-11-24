function audit = render_cross_city_replay(scenePath,outDir,varargin)
%RENDER_CROSS_CITY_REPLAY Export static and animated evidence from the viewer.
% The viewer reconstructs only frozen recorded commits; no optimizer is run.

parser=inputParser;
addRequired(parser,'scenePath',@(x)ischar(x)||isstring(x));
addRequired(parser,'outDir',@(x)ischar(x)||isstring(x));
addParameter(parser,'FigurePosition',[70 45 1920 1080], ...
    @(x)isnumeric(x)&&numel(x)==4&&all(isfinite(x))&&all(x(3:4)>0));
addParameter(parser,'PngResolution',300,@(x)isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>0);
addParameter(parser,'FrameRate',15,@(x)isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>0);
addParameter(parser,'VideoQuality',100,@(x)isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=0&&x<=100);
parse(parser,scenePath,outDir,varargin{:});options=parser.Results;

if ~exist(outDir,'dir'),mkdir(outDir);end
scene=jsondecode(fileread(scenePath));
viewer=open_cross_city_replay_viewer(scenePath,'Visible','off','AutoPlay',false, ...
    'FigurePosition',double(options.FigurePosition));
cleanup=onCleanup(@()safeClose(viewer));
viewer.setTime(double(scene.maximum_time));
state=viewer.getState();

% Export a clean axes-only paper figure, without interactive controls.
staticFig=figure('Visible','off','Color','w', ...
    'Position',[80 60 double(options.FigurePosition(3:4))],'Renderer','opengl');
staticAxes=copyobj(viewer.Axes,staticFig);
set(staticAxes,'Position',[.07 .08 .86 .86]);
pngPath=fullfile(outDir,'trajectory_3d.png');
pdfPath=fullfile(outDir,'trajectory_3d.pdf');
figPath=fullfile(outDir,'trajectory_3d.fig');
exportgraphics(staticAxes,pngPath,'Resolution',double(options.PngResolution));
exportgraphics(staticAxes,pdfPath,'ContentType','image','Resolution',double(options.PngResolution));
savefig(staticFig,figPath);
close(staticFig);

% GUI replay: the video intentionally includes time and event controls.
frameTimes=linspace(0,double(scene.maximum_time),121);
for k=1:numel(scene.events)
    event=sceneItem(scene.events,k);frameTimes(end+1)=double(event.time); %#ok<AGROW>
end
for k=1:numel(scene.commits)
    commit=sceneItem(scene.commits,k);
    frameTimes(end+1)=double(commit.time);frameTimes(end+1)=double(commit.finish); %#ok<AGROW>
end
frameTimes=unique(frameTimes(frameTimes>=0&frameTimes<=double(scene.maximum_time)));
gifPath=fullfile(outDir,'replay.gif');
mp4Path=fullfile(outDir,'replay.mp4');
finalStatusPath=fullfile(outDir,'final_status.png');
videoAvailable=true;videoError='';
try
    video=VideoWriter(mp4Path,'MPEG-4');video.FrameRate=double(options.FrameRate);
    video.Quality=double(options.VideoQuality);open(video);
catch error
    videoAvailable=false;videoError=[class(error) ': ' error.message];
end
for frameIndex=1:numel(frameTimes)
    viewer.setTime(frameTimes(frameIndex));drawnow;
    frame=getframe(viewer.Figure);rgb=frame2im(frame);[indexed,map]=rgb2ind(rgb,256);
    if frameIndex==1
        imwrite(indexed,map,gifPath,'gif','LoopCount',Inf,'DelayTime',.08);
    else
        imwrite(indexed,map,gifPath,'gif','WriteMode','append','DelayTime',.08);
    end
    if videoAvailable,writeVideo(video,rgb);end
end
imwrite(rgb,finalStatusPath);
if videoAvailable
    close(video);
elseif isfile(mp4Path)
    delete(mp4Path);
end

timerHandle=state.timer;
viewer.close();
timerCleanup=~isvalid(timerHandle);
clear cleanup;
summary=scene.state_index.final_summary;
taskCoverage=numel(summary.rescued)+numel(summary.revealed_not_rescued)+ ...
    numel(summary.confirmed_false_reports)+numel(summary.unrevealed_true_tasks);
searchCoverage=numel(summary.searched_task_found)+numel(summary.searched_empty)+numel(summary.unsearched);
audit=struct('status','passed','viewer_version','3.0', ...
    'city',char(scene.city),'matlab_version',version,'scene_sha256',fileSha256(scenePath), ...
    'commits_represented',numel(scene.commits),'resources_animated',numel(scene.resources), ...
    'frame_count',numel(frameTimes),'maximum_endpoint_error_m',state.maximum_endpoint_error_m, ...
    'true_altitude_scale',true,'display_vertical_enhancement_used',false, ...
    'building_lod_counts',state.lod_counts,'timer_cleanup_passed',timerCleanup, ...
    'gif_written',isfile(gifPath),'mp4_written',videoAvailable&&isfile(mp4Path), ...
    'final_status_png_written',isfile(finalStatusPath), ...
    'terminal_task_coverage',taskCoverage,'terminal_search_coverage',searchCoverage, ...
    'figure_position',double(options.FigurePosition), ...
    'png_resolution_dpi',double(options.PngResolution), ...
    'video_frame_rate',double(options.FrameRate), ...
    'video_quality',double(options.VideoQuality), ...
    'mp4_unavailable_reason',videoError,'static_png_written',isfile(pngPath), ...
    'static_pdf_written',isfile(pdfPath),'static_fig_written',isfile(figPath));
assert(audit.maximum_endpoint_error_m<=1e-8&&audit.timer_cleanup_passed);
assert(taskCoverage==numel(scene.tasks)&&searchCoverage==numel(scene.search_cells));
assert(audit.gif_written&&audit.final_status_png_written&&audit.static_png_written&&audit.static_pdf_written&&audit.static_fig_written);
fid=fopen(fullfile(outDir,'viewer_audit.json'),'w');assert(fid>=0);
fprintf(fid,'%s',jsonencode(audit,'PrettyPrint',true));fclose(fid);
disp(audit);
end

function value=sceneItem(array,index)
if iscell(array),value=array{index};else,value=array(index);end
end

function hash=fileSha256(path)
fid=fopen(path,'rb');assert(fid>=0);bytes=fread(fid,Inf,'*uint8');fclose(fid);
digest=java.security.MessageDigest.getInstance('SHA-256');digest.update(bytes);
hashBytes=typecast(digest.digest(),'uint8');hash=lower(reshape(dec2hex(hashBytes,2).',1,[]));
end

function safeClose(viewer)
try
    if isgraphics(viewer.Figure),viewer.close();end
catch
end
end
