function api = open_cross_city_replay_viewer(scenePath,varargin)
%OPEN_CROSS_CITY_REPLAY_VIEWER Native interactive viewer for a frozen replay.
%   API = OPEN_CROSS_CITY_REPLAY_VIEWER(SCENEPATH) opens an R2022a-compatible
%   3-D viewer. The source scene is read-only: all motion is reconstructed
%   from recorded commit geometry and edge durations.

parser = inputParser;
addRequired(parser,'scenePath',@(x)ischar(x)||isstring(x));
addParameter(parser,'Visible','on',@(x)ischar(x)||isstring(x));
addParameter(parser,'AutoPlay',false,@(x)islogical(x)&&isscalar(x));
addParameter(parser,'VerticalScale',1,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(parser,'FigurePosition',[70 45 1580 930], ...
    @(x)isnumeric(x)&&numel(x)==4&&all(isfinite(x))&&all(x(3:4)>0));
parse(parser,scenePath,varargin{:});
options = parser.Results;

scenePath = char(scenePath);
assert(isfile(scenePath),'Replay scene does not exist: %s',scenePath);
scene = jsondecode(fileread(scenePath));
required = {'city','commits','roads','buildings','resources','tasks','maximum_time','state_index'};
for k=1:numel(required)
    assert(isfield(scene,required{k}),'Scene is missing %s',required{k});
end

maximumTime = double(scene.maximum_time);
eventTimes = collectEventTimes(scene);
roles = resourceRoles(scene.resources);
resourceCount = numel(scene.resources);
currentTime = 0;
playbackSpeed = 1;
verticalFactor = double(options.VerticalScale);
cameraMode = 'perspective';
isPlaying = false;
layers = struct('buildings',true,'roads',true,'uav_routes',true, ...
    'ugv_routes',true,'task_labels',true,'search_cells',true,'trails',true);

trajectoryXY = trajectoryPoints(scene.commits);
[buildingClass,lodCounts] = classifyBuildings(scene.buildings,trajectoryXY);
roadClass = classifyRoads(scene.roads,trajectoryXY);

fig = figure('Name',[cityLabel(scene.city) ' mission replay'], ...
    'NumberTitle','off','Color',[0.975 0.98 0.985], ...
    'Visible',char(options.Visible),'Position',double(options.FigurePosition), ...
    'Renderer','opengl','CloseRequestFcn',@onClose);
ax = axes('Parent',fig,'Position',[0.045 0.19 0.71 0.76]);
hold(ax,'on'); grid(ax,'on'); box(ax,'on');
set(ax,'Color',[0.985 0.988 0.992],'GridColor',[0.72 0.75 0.78], ...
    'GridAlpha',0.16,'MinorGridAlpha',0.08,'FontName','Arial','FontSize',10);
xlabel(ax,'East (m)'); ylabel(ax,'North (m)'); zlabel(ax,'Altitude (m)');
camproj(ax,'orthographic'); view(ax,42,30);

groups = struct;
groups.roads = hggroup(ax,'Tag','roads');
groups.buildings = hggroup(ax,'Tag','buildings');
groups.uav_routes = hggroup(ax,'Tag','uav_routes');
groups.ugv_routes = hggroup(ax,'Tag','ugv_routes');
groups.task_labels = hggroup(ax,'Tag','task_labels');
groups.search_cells = hggroup(ax,'Tag','search_cells');
groups.trails = hggroup(ax,'Tag','trails');
groups.fixed_sites = hggroup(ax,'Tag','fixed_sites');
groups.actors = hggroup(ax,'Tag','actors');

drawRoadLod(ax,groups.roads,scene.roads,roadClass,verticalFactor);
drawBuildingLod(ax,groups.buildings,scene.buildings,buildingClass,verticalFactor);
drawRecordedRoutes(ax,groups,scene.commits,roles,verticalFactor);
[taskHandles,taskLabelHandles,searchHandles,searchLabelHandles] = ...
    drawSites(ax,groups,scene,verticalFactor);

trailHandles = gobjects(resourceCount,1);
actorHandles = gobjects(resourceCount,1);
for k=1:resourceCount
    r=item(scene.resources,k); initial=double(r.xyz(:)'); color=roleColor(char(r.role));
    trailHandles(k)=plot3(ax,initial(1),initial(2),verticalFactor*initial(3),'-', ...
        'Parent',groups.trails,'Color',0.72*color+0.28,'LineWidth',2.2, ...
        'HandleVisibility','off');
    actorHandles(k)=plot3(ax,initial(1),initial(2),verticalFactor*initial(3),'o', ...
        'Parent',groups.actors,'MarkerFaceColor',color,'MarkerEdgeColor','w', ...
        'LineWidth',1.2,'MarkerSize',8,'HandleVisibility','off');
end

setMissionBounds(ax,scene,trajectoryXY,verticalFactor);
legendHandles(ax);
titleHandle = title(ax,'','Interpreter','none','FontWeight','bold');

% Right-side controls.
panel = uipanel(fig,'Units','normalized','Position',[0.775 0.19 0.21 0.76], ...
    'Title','Mission controls','FontWeight','bold','BackgroundColor',[0.965 0.97 0.98]);
timeText = uicontrol(panel,'Style','text','Units','normalized', ...
    'Position',[0.05 0.925 0.9 0.045],'String','', ...
    'BackgroundColor',get(panel,'BackgroundColor'),'FontWeight','bold');
timeSlider = uicontrol(panel,'Style','slider','Units','normalized', ...
    'Position',[0.06 0.88 0.88 0.04],'Min',0,'Max',maximumTime,'Value',0, ...
    'SliderStep',sliderStep(maximumTime,eventTimes),'Callback',@onSlider);
uicontrol(panel,'Style','pushbutton','Units','normalized','Position',[0.05 0.81 0.19 0.05], ...
    'String','|<','TooltipString','Reset','Callback',@(~,~)setTime(0));
uicontrol(panel,'Style','pushbutton','Units','normalized','Position',[0.27 0.81 0.19 0.05], ...
    'String','< Event','Callback',@(~,~)stepEvent(-1));
playButton = uicontrol(panel,'Style','togglebutton','Units','normalized', ...
    'Position',[0.49 0.81 0.19 0.05],'String','Play','Callback',@onPlayToggle);
uicontrol(panel,'Style','pushbutton','Units','normalized','Position',[0.71 0.81 0.24 0.05], ...
    'String','Event >','Callback',@(~,~)stepEvent(1));
uicontrol(panel,'Style','text','Units','normalized','Position',[0.05 0.755 0.3 0.035], ...
    'String','Speed','BackgroundColor',get(panel,'BackgroundColor'));
speedPopup = uicontrol(panel,'Style','popupmenu','Units','normalized', ...
    'Position',[0.37 0.75 0.58 0.045],'String',{'0.5x','1x','2x','4x'}, ...
    'Value',2,'Callback',@onSpeed);

uicontrol(panel,'Style','text','Units','normalized','Position',[0.05 0.70 0.9 0.035], ...
    'String','Camera','FontWeight','bold','BackgroundColor',get(panel,'BackgroundColor'));
uicontrol(panel,'Style','pushbutton','Units','normalized','Position',[0.05 0.65 0.28 0.045], ...
    'String','3-D','Callback',@(~,~)setCamera('perspective'));
uicontrol(panel,'Style','pushbutton','Units','normalized','Position',[0.36 0.65 0.28 0.045], ...
    'String','Top','Callback',@(~,~)setCamera('top'));
uicontrol(panel,'Style','pushbutton','Units','normalized','Position',[0.67 0.65 0.28 0.045], ...
    'String','Follow UAV','Callback',@(~,~)setCamera('follow_uav'));

uicontrol(panel,'Style','text','Units','normalized','Position',[0.05 0.60 0.9 0.035], ...
    'String','Layers','FontWeight','bold','BackgroundColor',get(panel,'BackgroundColor'));
layerNames = {'buildings','roads','uav_routes','ugv_routes','task_labels','search_cells','trails'};
layerLabels = {'Buildings','Roads','UAV routes','UGV routes','Task labels','Search cells','Completed trails'};
layerControls = struct;
for k=1:numel(layerNames)
    row=0.56-(k-1)*0.041;
    layerControls.(layerNames{k})=uicontrol(panel,'Style','checkbox','Units','normalized', ...
        'Position',[0.08 row 0.84 0.035],'String',layerLabels{k},'Value',1, ...
        'BackgroundColor',get(panel,'BackgroundColor'),'Callback', ...
        @(source,~)setLayer(layerNames{k},logical(source.Value)));
end
verticalToggle = uicontrol(panel,'Style','checkbox','Units','normalized', ...
    'Position',[0.08 0.278 0.84 0.035],'String','Display-only altitude 3x', ...
    'Value',verticalFactor~=1,'BackgroundColor',get(panel,'BackgroundColor'), ...
    'Callback',@onVerticalToggle);
statusPanel = uipanel(panel,'Units','normalized','Position',[0.04 0.018 0.92 0.255], ...
    'Title','Current classification','FontWeight','bold','BackgroundColor',[1 1 1]);
statusRows=gobjects(8,1);
for k=1:numel(statusRows)
    statusRows(k)=uicontrol(statusPanel,'Style','text','Units','normalized', ...
        'Position',[0.025 0.875-(k-1)*0.12 0.95 0.115],'String','', ...
        'HorizontalAlignment','left','BackgroundColor',[1 1 1],'FontSize',8);
end

uicontrol(fig,'Style','text','Units','normalized','Position',[0.045 0.03 0.71 0.12], ...
    'String',sprintf(['Frozen kinematic replay — paths are recorded decisions, not re-optimized.  ' ...
    'Buildings: %d near / %d context / %d omitted.  Rotate, pan and zoom remain enabled during playback.'], ...
    lodCounts.near,lodCounts.context,lodCounts.omitted), ...
    'BackgroundColor',get(fig,'Color'),'HorizontalAlignment','left','FontSize',9);

viewerTimer = timer('Name',['cross_city_replay_' char(scene.city)], ...
    'ExecutionMode','fixedSpacing','Period',0.1,'BusyMode','drop','TimerFcn',@onTimer);

maximumEndpointError = endpointAudit(scene.commits);
updateDisplay();
rotate3d(fig,'on');
if options.AutoPlay
    set(playButton,'Value',1); onPlayToggle(playButton,[]);
end

api = struct('Figure',fig,'Axes',ax,'setTime',@setTime,'getState',@getState, ...
    'setLayer',@setLayer,'setCamera',@setCamera,'close',@closeViewer);

    function setTime(value)
        if ~isgraphics(fig),return;end
        currentTime=max(0,min(maximumTime,double(value)));
        set(timeSlider,'Value',currentTime);
        updateDisplay();
    end

    function state=getState()
        positions=zeros(resourceCount,3); names=cell(resourceCount,1);
        for index=1:resourceCount
            r=item(scene.resources,index); names{index}=char(r.resource);
            positions(index,:)=actorPosition(names{index},scene.commits,currentTime,double(r.xyz(:)'));
        end
        taskStates=statesAtTime(scene.state_index.tasks,currentTime);
        searchStates=statesAtTime(scene.state_index.search_cells,currentTime);
        statusLines=missionStatus(scene,currentTime,taskStates,searchStates);
        state=struct('city',char(scene.city),'current_time',currentTime, ...
            'maximum_time',maximumTime,'positions',positions,'resource_names',{names}, ...
            'layers',layers,'camera_mode',cameraMode,'vertical_factor',verticalFactor, ...
            'event_times',eventTimes,'maximum_endpoint_error_m',maximumEndpointError, ...
            'timer',viewerTimer,'timer_running',strcmp(viewerTimer.Running,'on'), ...
            'lod_counts',lodCounts,'task_states',taskStates, ...
            'search_states',searchStates,'status_lines',{statusLines}, ...
            'task_label_strings',{handleStrings(taskLabelHandles)}, ...
            'search_label_strings',{handleStrings(searchLabelHandles)}, ...
            'status_scrollbar_required',false,'figure_position',double(get(fig,'Position')));
    end

    function setLayer(name,value)
        name=lower(strrep(char(name),'-','_'));
        assert(isfield(layers,name),'Unknown viewer layer: %s',name);
        layers.(name)=logical(value);
        if isgraphics(groups.(name)),set(groups.(name),'Visible',onOff(layers.(name)));end
        if isfield(layerControls,name)&&isgraphics(layerControls.(name))
            set(layerControls.(name),'Value',layers.(name));
        end
    end

    function setCamera(name)
        name=lower(strrep(char(name),'-','_'));
        switch name
            case 'perspective'
                cameraMode=name; camproj(ax,'orthographic'); view(ax,42,30); setMissionBounds(ax,scene,trajectoryXY,verticalFactor);
            case 'top'
                cameraMode=name; camproj(ax,'orthographic'); view(ax,0,90); setMissionBounds(ax,scene,trajectoryXY,verticalFactor);
            case {'follow','follow_uav'}
                cameraMode='follow_uav'; view(ax,42,30); updateFollowCamera();
            otherwise
                error('Unknown camera mode: %s',name);
        end
    end

    function updateDisplay()
        positions=zeros(resourceCount,3);
        for index=1:resourceCount
            r=item(scene.resources,index); resource=char(r.resource);
            [positions(index,:),trail]=actorPosition(resource,scene.commits,currentTime,double(r.xyz(:)'));
            set(actorHandles(index),'XData',positions(index,1),'YData',positions(index,2), ...
                'ZData',verticalFactor*positions(index,3));
            set(trailHandles(index),'XData',trail(:,1),'YData',trail(:,2), ...
                'ZData',verticalFactor*trail(:,3));
        end
        taskStates=statesAtTime(scene.state_index.tasks,currentTime);
        searchStates=statesAtTime(scene.state_index.search_cells,currentTime);
        updateSiteStates(scene,taskHandles,taskLabelHandles,searchHandles, ...
            searchLabelHandles,taskStates,searchStates);
        set(timeText,'String',sprintf('t = %.2f / %.2f min',currentTime,maximumTime));
        set(titleHandle,'String',sprintf('%s — frozen rolling response replay | t = %.2f min', ...
            cityLabel(scene.city),currentTime));
        updateStatusRows(statusRows,missionStatus(scene,currentTime,taskStates,searchStates));
        if strcmp(cameraMode,'follow_uav'),updateFollowCamera();end
        drawnow limitrate;
    end

    function updateFollowCamera()
        target=[];
        for index=1:resourceCount
            r=item(scene.resources,index);
            if strcmp(char(r.role),'verification')
                target=[get(actorHandles(index),'XData'),get(actorHandles(index),'YData')]; %#ok<AGROW>
                break;
            end
        end
        if isempty(target),return;end
        xlim(ax,target(1)+[-420 420]); ylim(ax,target(2)+[-420 420]);
        zlim(ax,[0 max(100,verticalFactor*130)]); view(ax,42,30);
    end

    function stepEvent(direction)
        if direction>0
            next=eventTimes(find(eventTimes>currentTime+1e-10,1,'first'));
        else
            next=eventTimes(find(eventTimes<currentTime-1e-10,1,'last'));
        end
        if ~isempty(next),setTime(next);end
    end

    function onSlider(source,~),setTime(source.Value);end
    function onSpeed(source,~)
        values=[0.5 1 2 4]; playbackSpeed=values(source.Value);
    end
    function onPlayToggle(source,~)
        isPlaying=logical(source.Value);
        if isPlaying
            set(source,'String','Pause');
            if strcmp(viewerTimer.Running,'off'),start(viewerTimer);end
        else
            set(source,'String','Play');
            if strcmp(viewerTimer.Running,'on'),stop(viewerTimer);end
        end
    end
    function onTimer(~,~)
        if ~isgraphics(fig),return;end
        next=currentTime+0.5*playbackSpeed;
        if next>=maximumTime
            setTime(maximumTime); set(playButton,'Value',0,'String','Play'); isPlaying=false; stop(viewerTimer);
        else
            setTime(next);
        end
    end
    function onVerticalToggle(source,~)
        if source.Value,verticalFactor=3;else,verticalFactor=1;end
        applyVerticalScale(fig,verticalFactor);
        updateDisplay(); setCamera(cameraMode);
    end
    function onClose(~,~),closeViewer();end
    function closeViewer()
        if isvalid(viewerTimer)
            if strcmp(viewerTimer.Running,'on'),stop(viewerTimer);end
            delete(viewerTimer);
        end
        if isgraphics(fig)
            set(fig,'CloseRequestFcn',''); delete(fig);
        end
    end
end

function times=collectEventTimes(scene)
times=[0;double(scene.maximum_time)];
if isfield(scene,'events')&&~isempty(scene.events)
    for k=1:numel(scene.events),e=item(scene.events,k);times(end+1,1)=double(e.time);end %#ok<AGROW>
end
if ~isempty(scene.commits)
    for k=1:numel(scene.commits)
        c=item(scene.commits,k);times(end+1,1)=double(c.time);times(end+1,1)=double(c.finish); %#ok<AGROW>
    end
end
times=unique(times(isfinite(times)&times>=0&times<=double(scene.maximum_time)));
end

function step=sliderStep(maximumTime,eventTimes)
if maximumTime<=0,step=[1 1];return;end
minimum=1/maximumTime;
if numel(eventTimes)>1,major=min(1,max(minimum,median(diff(eventTimes))/maximumTime));else,major=.1;end
step=[min(1,minimum),major];
end

function points=trajectoryPoints(commits)
points=zeros(0,2);
for k=1:numel(commits),c=item(commits,k);p=double(c.xyz);points=[points;p(:,1:2)];end %#ok<AGROW>
if size(points,1)>600,points=points(round(linspace(1,size(points,1),600)),:);end
end

function [classes,counts]=classifyBuildings(buildings,trajectoryXY)
classes=zeros(numel(buildings),1);
for k=1:numel(buildings)
    b=item(buildings,k); ring=double(b.xyz); center=mean(ring(:,1:2),1);
    distance=min(hypot(trajectoryXY(:,1)-center(1),trajectoryXY(:,2)-center(2)));
    if distance<=90,classes(k)=1;elseif distance<=260,classes(k)=2;else,classes(k)=3;end
end
counts=struct('near',sum(classes==1),'context',sum(classes==2),'omitted',sum(classes==3));
end

function classes=classifyRoads(roads,trajectoryXY)
classes=zeros(numel(roads),1);
for k=1:numel(roads)
    r=item(roads,k);p=double(r.xyz);center=mean(p(:,1:2),1);
    distance=min(hypot(trajectoryXY(:,1)-center(1),trajectoryXY(:,2)-center(2)));
    if distance<=220,classes(k)=1;elseif distance<=520,classes(k)=2;else,classes(k)=3;end
end
end

function drawRoadLod(ax,parent,roads,classes,factor)
colors={[0.36 0.39 0.43],[0.65 0.67 0.70],[0.82 0.83 0.84]}; widths=[0.9 0.5 0.25];
for classIndex=1:3
    xyz=joinedLines(roads,classes==classIndex);
    if isempty(xyz),continue;end
    h=plot3(ax,xyz(:,1),xyz(:,2),factor*xyz(:,3),'Parent',parent, ...
        'Color',colors{classIndex},'LineWidth',widths(classIndex),'HandleVisibility','off');
    setappdata(h,'BaseZData',xyz(:,3));
end
end

function xyz=joinedLines(values,mask)
xyz=zeros(0,3);
indices=find(mask(:)');
for k=indices
    v=item(values,k); p=double(v.xyz); xyz=[xyz;p;nan(1,3)]; %#ok<AGROW>
end
end

function drawBuildingLod(ax,parent,buildings,classes,factor)
for classIndex=1:2
    for unknown=0:1
        mask=classes==classIndex;
        for k=1:numel(buildings)
            b=item(buildings,k); flag=isfield(b,'height_unknown')&&logical(b.height_unknown);
            mask(k)=mask(k)&&(flag==logical(unknown));
        end
        [vertices,faces]=buildingMesh(buildings,mask,classIndex==2);
        if isempty(vertices),continue;end
        baseVertices=vertices; vertices(:,3)=factor*vertices(:,3);
        if unknown,color=[0.76 0.63 0.38];else,color=[0.46 0.52 0.60];end
        if classIndex==1,alpha=.72;edgeAlpha=.12;else,alpha=.30;edgeAlpha=.02;end
        h=patch(ax,'Parent',parent,'Vertices',vertices,'Faces',faces,'FaceColor',color, ...
            'FaceAlpha',alpha,'EdgeColor',[0.36 0.39 0.43],'EdgeAlpha',edgeAlpha, ...
            'LineWidth',0.2,'HandleVisibility','off');
        setappdata(h,'BaseVertices',baseVertices);
    end
end
end

function [vertices,faces]=buildingMesh(buildings,mask,footprintOnly)
vertices=zeros(0,3);faceCells={};
for k=find(mask(:)')
    b=item(buildings,k);ring=double(b.xyz);height=double(b.height);
    if footprintOnly,height=min(height,2.5);end
    if size(ring,1)>1&&norm(ring(1,:)-ring(end,:))<1e-8,ring(end,:)=[];end
    n=size(ring,1);if n<3,continue;end
    start=size(vertices,1);base=ring;base(:,3)=0;top=base;top(:,3)=height;
    vertices=[vertices;base;top]; %#ok<AGROW>
    bottom=start+(1:n);roof=start+n+(1:n);faceCells{end+1}=roof; %#ok<AGROW>
    for q=1:n,q2=mod(q,n)+1;faceCells{end+1}=[bottom(q),bottom(q2),roof(q2),roof(q)];end %#ok<AGROW>
end
if isempty(faceCells),faces=zeros(0,4);return;end
width=max(cellfun(@numel,faceCells));faces=nan(numel(faceCells),width);
for k=1:numel(faceCells),faces(k,1:numel(faceCells{k}))=faceCells{k};end
end

function drawRecordedRoutes(ax,groups,commits,roles,factor)
for k=1:numel(commits)
    c=item(commits,k);p=double(c.xyz);resource=char(c.resource);
    if isKey(roles,resource),role=roles(resource);else,role='unknown';end
    if strcmp(role,'verification'),parent=groups.uav_routes;else,parent=groups.ugv_routes;end
    color=.54*roleColor(role)+.46;
    h=plot3(ax,p(:,1),p(:,2),factor*p(:,3),'Parent',parent,'Color',color, ...
        'LineStyle',phaseStyle(char(c.phase)),'LineWidth',1.15,'HandleVisibility','off');
    setappdata(h,'BaseZData',p(:,3));
end
end

function [taskHandles,taskLabelHandles,searchHandles,searchLabelHandles]=drawSites(ax,groups,scene,factor)
for k=1:numel(scene.resources)
    r=item(scene.resources,k);p=double(r.xyz(:)');
    h=scatter3(ax,p(1),p(2),factor*p(3),48,'s','filled','Parent',groups.fixed_sites, ...
        'MarkerFaceColor',[.15 .17 .20],'MarkerEdgeColor','w','HandleVisibility','off');
    setappdata(h,'BaseZData',p(3));
end
taskHandles=gobjects(numel(scene.tasks),1);
taskLabelHandles=gobjects(numel(scene.tasks),1);
for k=1:numel(scene.tasks)
    t=item(scene.tasks,k);p=double(t.xyz(:)');
    taskHandles(k)=scatter3(ax,p(1),p(2),factor*p(3),76,'^','Parent',groups.fixed_sites, ...
        'MarkerFaceColor',[.42 .50 .62],'MarkerEdgeColor','k','LineWidth',1.2,'HandleVisibility','off');
    setappdata(taskHandles(k),'BaseZData',p(3));
    offsets=[18 18;18 -28;-95 18;-95 -28;18 18];offset=offsets(mod(k-1,size(offsets,1))+1,:);
    taskLabelHandles(k)=text(ax,p(1)+offset(1),p(2)+offset(2),factor*(p(3)+5),char(t.report), ...
        'Parent',groups.task_labels,'FontSize',8,'FontWeight','bold','Interpreter','none', ...
        'Color',[.12 .12 .14],'Clipping','on');
    setappdata(taskLabelHandles(k),'BasePosition',get(taskLabelHandles(k),'Position'));
end
searchHandles=gobjects(numel(scene.search_cells),1);
searchLabelHandles=gobjects(numel(scene.search_cells),1);
if isfield(scene,'search_cells')
    for k=1:numel(scene.search_cells)
        c=item(scene.search_cells,k);p=double(c.xyz);
        searchHandles(k)=scatter3(ax,p(:,1),p(:,2),factor*p(:,3),58,'d','Parent',groups.search_cells, ...
            'MarkerFaceColor','none','MarkerEdgeColor',[.42 .45 .50], ...
            'LineWidth',1.4,'HandleVisibility','off');
        setappdata(searchHandles(k),'BaseZData',p(:,3));
        center=mean(p,1);searchOffsets=[-82 -34;-82 34;38 -34;38 34];
        searchOffset=searchOffsets(mod(k-1,size(searchOffsets,1))+1,:);
        searchLabelHandles(k)=text(ax,center(1)+searchOffset(1),center(2)+searchOffset(2),factor*(center(3)+3), ...
            char(c.cell_id),'Parent',groups.search_cells,'FontSize',8, ...
            'FontWeight','bold','Interpreter','none','Color',[.30 .32 .36],'Clipping','on');
        setappdata(searchLabelHandles(k),'BasePosition',get(searchLabelHandles(k),'Position'));
    end
end
end

function applyVerticalScale(fig,factor)
objects=findall(fig);
for k=1:numel(objects)
    h=objects(k);
    if isappdata(h,'BaseVertices')
        vertices=getappdata(h,'BaseVertices');vertices(:,3)=factor*vertices(:,3);set(h,'Vertices',vertices);
    elseif isappdata(h,'BasePosition')
        position=getappdata(h,'BasePosition');position(3)=factor*position(3);set(h,'Position',position);
    elseif isappdata(h,'BaseZData')
        set(h,'ZData',factor*getappdata(h,'BaseZData'));
    end
end
end

function setMissionBounds(ax,scene,trajectoryXY,factor)
points=trajectoryXY;
for k=1:numel(scene.tasks),t=item(scene.tasks,k);p=double(t.xyz(:)');points=[points;p(1:2)];end %#ok<AGROW>
for k=1:numel(scene.resources),r=item(scene.resources,k);p=double(r.xyz(:)');points=[points;p(1:2)];end %#ok<AGROW>
minimum=min(points,[],1);maximum=max(points,[],1);span=max(maximum-minimum,[500 500]);margin=.07*span;
xlim(ax,[minimum(1)-margin(1),maximum(1)+margin(1)]);ylim(ax,[minimum(2)-margin(2),maximum(2)+margin(2)]);
heights=0;
for k=1:numel(scene.commits),c=item(scene.commits,k);p=double(c.xyz);heights=max(heights,max(p(:,3)));end
zlim(ax,[0,max(80,factor*(heights+20))]);daspect(ax,[1 1 1]);
end

function [position,trail]=actorPosition(resource,commits,time,initial)
position=initial;trail=initial;relevant=[];
for k=1:numel(commits),c=item(commits,k);if strcmp(char(c.resource),resource),relevant(end+1)=k;end,end %#ok<AGROW>
if isempty(relevant),return;end
times=arrayfun(@(index)double(item(commits,index).time),relevant);[~,order]=sort(times);relevant=relevant(order);
for index=relevant
    c=item(commits,index);start=double(c.time);finish=double(c.finish);xyz=double(c.xyz);durations=double(c.edge_minutes(:));
    if time<start,break;end
    if norm(trail(end,:)-xyz(1,:))>1e-9,trail=[trail;xyz(1,:)];end %#ok<AGROW>
    if time>=finish
        trail=[trail;xyz(2:end,:)];position=xyz(end,:);continue; %#ok<AGROW>
    end
    elapsed=max(0,time-start);travel=sum(durations);
    if elapsed>=travel,trail=[trail;xyz(2:end,:)];position=xyz(end,:);return;end %#ok<AGROW>
    left=elapsed;
    for edge=1:numel(durations)
        duration=durations(edge);
        if left<=duration||edge==numel(durations)
            if duration<=eps,alpha=1;else,alpha=max(0,min(1,left/duration));end
            position=xyz(edge,:)+alpha*(xyz(edge+1,:)-xyz(edge,:));
            if edge>1,trail=[trail;xyz(2:edge,:)];end %#ok<AGROW>
            if norm(trail(end,:)-position)>1e-10,trail=[trail;position];end %#ok<AGROW>
            return;
        end
        left=left-duration;
    end
end
end

function errorValue=endpointAudit(commits)
errorValue=0;
for k=1:numel(commits)
    c=item(commits,k);xyz=double(c.xyz);durations=double(c.edge_minutes(:));left=sum(durations);position=xyz(1,:);
    for edge=1:numel(durations)
        duration=durations(edge);
        if left<=duration||edge==numel(durations)
            if duration<=eps,alpha=1;else,alpha=max(0,min(1,left/duration));end
            position=xyz(edge,:)+alpha*(xyz(edge+1,:)-xyz(edge,:));break;
        end
        left=left-duration;
    end
    errorValue=max(errorValue,norm(position-xyz(end,:)));
end
end

function states=statesAtTime(entries,time)
states=struct;
for k=1:numel(entries)
    entry=item(entries,k);transitions=entry.transitions;state='';
    for q=1:numel(transitions)
        transition=item(transitions,q);
        if double(transition.time)<=double(time)+1e-9,state=char(transition.state);end
    end
    states.(matlab.lang.makeValidName(char(entry.id)))=state;
end
end

function state=stateForId(states,id)
field=matlab.lang.makeValidName(char(id));
assert(isfield(states,field),'Missing replay state for %s',char(id));
state=states.(field);
end

function updateSiteStates(scene,taskHandles,taskLabelHandles,searchHandles,searchLabelHandles,taskStates,searchStates)
for k=1:numel(scene.tasks)
    task=item(scene.tasks,k);id=char(task.report);state=stateForId(taskStates,id);
    [marker,face,edge,visible]=taskStyle(state);
    set(taskHandles(k),'Marker',marker,'MarkerFaceColor',face, ...
        'MarkerEdgeColor',edge,'Visible',visible);
    set(taskLabelHandles(k),'String',id,'Visible',visible);
end
for k=1:numel(scene.search_cells)
    cellItem=item(scene.search_cells,k);id=char(cellItem.cell_id);state=stateForId(searchStates,id);
    [marker,face,edge]=searchStyle(state);
    set(searchHandles(k),'Marker',marker,'MarkerFaceColor',face,'MarkerEdgeColor',edge);
    set(searchLabelHandles(k),'String',id,'Color',edge);
end
end

function [marker,face,edge,visible]=taskStyle(state)
visible='on';edge=[.10 .10 .12];
switch state
    case 'not_yet_revealed'
        marker='^';face=[.8 .8 .8];edge=[.8 .8 .8];visible='off';name='Not yet revealed';
    case 'pending_verification'
        marker='^';face=[.42 .50 .62];name='Pending verification';
    case 'revealed_waiting_rescue'
        marker='^';face=[.96 .60 .08];name='Revealed / waiting rescue';
    case 'rescue_in_progress'
        marker='p';face=[.90 .22 .14];name='Rescue in progress';
    case 'rescued'
        marker='o';face=[.10 .64 .28];name='Rescued';
    case 'confirmed_false_report'
        marker='x';face='none';edge=[.36 .36 .38];name='Confirmed false report';
    case 'unrevealed_true_task'
        marker='h';face=[.58 .12 .68];edge=[.24 .04 .30];name='Unrevealed true task';
    otherwise
        error('Unknown task replay state: %s',state);
end
end

function [marker,face,edge]=searchStyle(state)
switch state
    case 'unsearched'
        marker='d';face='none';edge=[.42 .45 .50];name='Unsearched';
    case 'search_in_progress'
        marker='d';face=[.12 .48 .86];edge=[.04 .20 .44];name='Searching';
    case 'searched_task_found'
        marker='d';face=[.10 .64 .28];edge=[.03 .30 .12];name='Searched / task found';
    case 'searched_empty'
        marker='x';face='none';edge=[.36 .36 .38];name='Searched / empty';
    otherwise
        error('Unknown search replay state: %s',state);
end
end

function lines=missionStatus(scene,time,taskStates,searchStates)
lines={sprintf('Mission time: %.2f min',time),'TASK STATUS'};
lines{end+1}=statusPair('Rescued',idsInState(taskStates,{'rescued'}), ...
    'Revealed / waiting rescue',idsInState(taskStates,{'pending_verification','revealed_waiting_rescue','rescue_in_progress'}));
lines{end+1}=statusPair('Confirmed false reports',idsInState(taskStates,{'confirmed_false_report'}), ...
    'Unrevealed true tasks',idsInState(taskStates,{'unrevealed_true_task'}));
lines{end+1}='SEARCH STATUS';
lines{end+1}=statusPair('Searched / task found',idsInState(searchStates,{'searched_task_found'}), ...
    'Searched / empty',idsInState(searchStates,{'searched_empty'}));
lines{end+1}=statusPair('Searching',idsInState(searchStates,{'search_in_progress'}), ...
    'Unsearched',idsInState(searchStates,{'unsearched'}));
if time<double(scene.maximum_time)-1e-9
    lines{end+1}='Endpoint-only hidden truth remains concealed.';
else
    lines{end+1}='FINAL CLASSIFICATION: every task and search region assigned.';
end
end

function ids=idsInState(states,targetStates)
fields=fieldnames(states);ids={};
for k=1:numel(fields)
    if any(strcmp(states.(fields{k}),targetStates)),ids{end+1}=fields{k};end %#ok<AGROW>
end
end

function text=statusPair(leftName,leftIds,rightName,rightIds)
text=sprintf('%s %d: %s  |  %s %d: %s',leftName,numel(leftIds),idText(leftIds), ...
    rightName,numel(rightIds),idText(rightIds));
end

function text=idText(ids)
if isempty(ids),text='none';else,text=strjoin(ids,', ');end
end

function strings=handleStrings(handles)
strings=cell(numel(handles),1);
for k=1:numel(handles),strings{k}=char(get(handles(k),'String'));end
end

function updateStatusRows(handles,lines)
assert(numel(lines)<=numel(handles),'Status panel has more lines than fixed rows');
for k=1:numel(handles)
    if k<=numel(lines)
        set(handles(k),'String',lines{k},'Visible','on');
    else
        set(handles(k),'String','','Visible','off');
    end
end
end

function map=resourceRoles(resources)
map=containers.Map('KeyType','char','ValueType','char');
for k=1:numel(resources),r=item(resources,k);map(char(r.resource))=char(r.role);end
end

function color=roleColor(role)
switch role
    case 'verification',color=[.05 .38 .82];
    case 'rescue',color=[.86 .16 .12];
    case 'triage',color=[.08 .58 .28];
    otherwise,color=[.35 .35 .35];
end
end

function style=phaseStyle(phase)
switch phase
    case 'search',style=':';
    case 'verification',style='-';
    case 'intervention',style='--';
    otherwise,style='-.';
end
end

function legendHandles(ax)
h(1)=plot3(ax,nan,nan,nan,'-','Color',roleColor('verification'),'LineWidth',2,'DisplayName','UAV verification/search');
h(2)=plot3(ax,nan,nan,nan,'-','Color',roleColor('rescue'),'LineWidth',2,'DisplayName','UGV rescue');
h(3)=plot3(ax,nan,nan,nan,'-','Color',roleColor('triage'),'LineWidth',2,'DisplayName','UGV triage');
h(4)=scatter3(ax,nan,nan,nan,60,'^','filled','MarkerFaceColor',[.42 .50 .62],'DisplayName','Pending verification');
h(5)=scatter3(ax,nan,nan,nan,60,'p','filled','MarkerFaceColor',[.90 .22 .14],'DisplayName','Rescue in progress');
h(6)=scatter3(ax,nan,nan,nan,60,'o','filled','MarkerFaceColor',[.10 .64 .28],'DisplayName','Rescued / search found');
h(7)=scatter3(ax,nan,nan,nan,60,'x','MarkerEdgeColor',[.36 .36 .38],'DisplayName','False report / empty search');
legend(ax,h,'Location','northwest','Color',[1 1 1],'FontSize',8);
end

function value=item(array,index)
if iscell(array),value=array{index};else,value=array(index);end
end
function label=cityLabel(city)
switch char(city),case 'lower_manhattan',label='Lower Manhattan';case 'chicago',label='Chicago';otherwise,label=char(city);end
end
function value=onOff(flag),if flag,value='on';else,value='off';end,end
