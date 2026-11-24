function results = test_cross_city_replay_viewer()
%TEST_CROSS_CITY_REPLAY_VIEWER Programmatic two-city viewer acceptance test.

repoRoot = fileparts(fileparts(mfilename('fullpath')));
cities = {'lower_manhattan','chicago'};
results = repmat(struct('city','','status','','maximum_endpoint_error_m',NaN, ...
    'timer_cleanup_passed',false),numel(cities),1);

for cityIndex = 1:numel(cities)
    city = cities{cityIndex};
    scenePath = fullfile(repoRoot,'outputs','cross_city_matlab_replay_v3',city,'scene.json');
    assert(isfile(scenePath),'Missing frozen scene: %s',scenePath);
    scene = jsondecode(fileread(scenePath));

    requestedPosition=[120 80 1280 720];
    viewer = open_cross_city_replay_viewer(scenePath,'Visible','off','AutoPlay',false, ...
        'FigurePosition',requestedPosition);
    required = {'Figure','setTime','getState','setLayer','setCamera','close'};
    for k = 1:numel(required)
        assert(isfield(viewer,required{k}),'Viewer contract is missing %s',required{k});
    end

    initialState = viewer.getState();
    assert(initialState.current_time == 0);
    assert(max(abs(initialState.figure_position-requestedPosition))<1e-10);
    assert(all(isfinite(initialState.positions),'all'));
    assert(isfield(initialState,'task_states')&&isfield(initialState,'search_states'));
    assert(isequal(initialState.task_states,expectedStates(scene.state_index.tasks,0)));
    assert(isequal(initialState.search_states,expectedStates(scene.state_index.search_cells,0)));
    assert(isequal(initialState.task_label_strings,sceneIds(scene.tasks,'report')));
    assert(isequal(initialState.search_label_strings,sceneIds(scene.search_cells,'cell_id')));
    assert(~initialState.status_scrollbar_required);

    eventTimes = [0;double(scene.maximum_time)];
    for k=1:numel(scene.events),e=sceneItem(scene.events,k);eventTimes(end+1,1)=double(e.time);end %#ok<AGROW>
    for k=1:numel(scene.commits)
        c=sceneItem(scene.commits,k);eventTimes(end+1,1)=double(c.time);eventTimes(end+1,1)=double(c.finish); %#ok<AGROW>
    end
    eventTimes=unique(eventTimes);
    interior = eventTimes(find(eventTimes>0 & eventTimes<double(scene.maximum_time),1,'first'));
    viewer.setTime(interior);
    interiorState = viewer.getState();
    assert(abs(interiorState.current_time-interior)<1e-12);
    assert(all(isfinite(interiorState.positions),'all'));

    searchCommit=findCommit(scene.commits,'search');
    searchTime=(double(searchCommit.time)+double(searchCommit.finish))/2;
    viewer.setTime(searchTime);
    searchState=viewer.getState();
    searchId=extractAfter(char(searchCommit.report),'search:');
    assert(strcmp(searchState.search_states.(searchId),'search_in_progress'));

    rescueCommit=findCommit(scene.commits,'intervention');
    rescueTime=double(rescueCommit.time)+1e-6;
    viewer.setTime(rescueTime);
    rescueState=viewer.getState();
    assert(strcmp(rescueState.task_states.(char(rescueCommit.report)),'rescue_in_progress'));

    viewer.setTime(double(scene.maximum_time));
    finalState = viewer.getState();
    assert(isequal(finalState.task_states,expectedStates(scene.state_index.tasks,double(scene.maximum_time))));
    assert(isequal(finalState.search_states,expectedStates(scene.state_index.search_cells,double(scene.maximum_time))));
    assert(isequal(finalState.task_label_strings,sceneIds(scene.tasks,'report')));
    assert(isequal(finalState.search_label_strings,sceneIds(scene.search_cells,'cell_id')));
    mapLabels=strjoin([finalState.task_label_strings;finalState.search_label_strings],newline);
    assert(~contains(mapLabels,'Rescued')&&~contains(mapLabels,'Confirmed false report'));
    assert(~contains(mapLabels,'Searched / task found'));
    status=string(strjoin(finalState.status_lines,newline));
    categories=["Rescued","Revealed / waiting rescue","Confirmed false reports", ...
        "Unrevealed true tasks","Searched / task found","Searched / empty","Unsearched"];
    assert(all(contains(status,categories)),'Final status panel omits a terminal category');
    assert(~finalState.status_scrollbar_required,'Status panel still requires scrolling');
    viewer.setTime(interior);
    backwardState = viewer.getState();
    assert(max(abs(backwardState.positions-interiorState.positions),[],'all')<1e-10, ...
        'Backward scrubbing is not deterministic');
    assert(isequal(backwardState.task_states,interiorState.task_states));
    assert(isequal(backwardState.search_states,interiorState.search_states));
    viewer.setTime(double(scene.maximum_time));
    repeatedFinal = viewer.getState();
    assert(max(abs(repeatedFinal.positions-finalState.positions),[],'all')<1e-10, ...
        'Repeated horizon reconstruction is not deterministic');

    timeBeforeToggle = repeatedFinal.current_time;
    viewer.setLayer('buildings',false);
    hiddenState = viewer.getState();
    assert(~hiddenState.layers.buildings && hiddenState.current_time==timeBeforeToggle);
    viewer.setLayer('buildings',true);
    viewer.setCamera('top');
    viewer.setCamera('perspective');

    endpointError = repeatedFinal.maximum_endpoint_error_m;
    assert(endpointError<=1e-8,'Endpoint error %.3g m exceeds tolerance',endpointError);
    timerHandle = repeatedFinal.timer;
    viewer.close();
    drawnow;
    cleanupPassed = ~isvalid(timerHandle);
    assert(cleanupPassed,'Viewer timer survived figure close');

    results(cityIndex) = struct('city',city,'status','passed', ...
        'maximum_endpoint_error_m',endpointError,'timer_cleanup_passed',cleanupPassed);
end

disp(results);
end

function value=sceneItem(array,index)
if iscell(array),value=array{index};else,value=array(index);end
end

function states=expectedStates(items,time)
states=struct;
for k=1:numel(items)
    entry=sceneItem(items,k);transitions=entry.transitions;state='';
    for q=1:numel(transitions)
        transition=sceneItem(transitions,q);
        if double(transition.time)<=time+1e-9,state=char(transition.state);end
    end
    states.(char(entry.id))=state;
end
end

function commit=findCommit(commits,phase)
for k=1:numel(commits)
    candidate=sceneItem(commits,k);
    if strcmp(char(candidate.phase),phase),commit=candidate;return;end
end
error('Missing %s commit',phase);
end

function ids=sceneIds(items,field)
ids=cell(numel(items),1);
for k=1:numel(items),entry=sceneItem(items,k);ids{k}=char(entry.(field));end
end
