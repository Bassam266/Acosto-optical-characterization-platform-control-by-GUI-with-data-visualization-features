function instrumentControlGUI
% INSTRUMENTCONTROLGUI  Friendly interface to configure the signal
% generator, oscilloscope and XYZ motor stage, run a Z echo scan, and
% analyse the echoes.
%
%   >> instrumentControlGUI
%
% Wraps the SAME classes your script uses: DG5000Pro, PIMotorController,
% T3DSO2502A. Those class .m files must be on the MATLAB path.

%% ---------------------------------------------------------------- state --
S = struct();
S.gen   = [];
S.osc   = [];
S.motor = struct('X',[],'Y',[],'Z',[]);
S.range = struct('X',[0 0],'Y',[0 0],'Z',[0 0]);
S.fsActual = [];
S.stopScan = false;
S.zscan = [];     % raw scan: positions_mm, data_all, t
S.zres  = [];     % analysis results: snrdB, peakIdx, gates, bestK ...
S.mat   = [];     % material analysis: f, Amplitude, FFT_complex, alpha, c2, rho2
S.xyscan = [];    % xy raster results: allData, allX, allY, t
S.xyres  = [];    % xy analysis: snr/amp maps, bestI, bestJ, gates
S.sens   = [];    % sensitivity / NEP results
S.fpscan = [];    % FP sweep data: allData, t
S.fsweep = [];    % generator frequency sweep: allData, freqs, ampPk, t, pos
S.fp     = [];    % FP frequency-response results
S.strace = [];    % single captured trace (data, t)
S.settingsFile = fullfile(pwd,'instrumentGUI_settings.mat');  % one-click save target
S.ui    = struct();

%% ----------------------------------------------------------------- theme --
FONT   = 'Segoe UI';                 % falls back gracefully if unavailable
BG     = [0.96 0.97 0.99];           % window background
PANEL  = [1.00 1.00 1.00];           % card / panel background
ACCENT = [0.20 0.45 0.85];           % primary action
ACCENTD= [0.13 0.30 0.58];           % accent (dark, for titles/text)
DANGER = [0.80 0.27 0.27];           % stop / disconnect
OKGRN  = [0.16 0.55 0.34];
NEUBG  = [0.92 0.94 0.98];           % neutral button background
NEUTX  = [0.16 0.22 0.34];
MUTED  = [0.45 0.50 0.58];

%% --------------------------------------------------------------- figure --
fig = uifigure('Name','Lab Instrument Control','Position',[80 80 1000 790], ...
    'Color',BG);
main = uigridlayout(fig,[3 1]);
main.RowHeight    = {40,'1x',150};
main.ColumnWidth  = {'1x'};
main.BackgroundColor = BG;

hdr = uigridlayout(main,[1 3]); hdr.Layout.Row = 1;
hdr.ColumnWidth = {'1x',140,140}; hdr.Padding = [6 2 6 2]; hdr.BackgroundColor = BG;
uilabel(hdr,'Text','  Lab Instrument Control', ...
    'FontName',FONT,'FontSize',18,'FontWeight','bold','FontColor',ACCENTD);
uibutton(hdr,'Text','Save settings','ButtonPushedFcn',@(~,~)quickSaveSettings());
uibutton(hdr,'Text','Load settings','ButtonPushedFcn',@(~,~)loadAllSettings());

tg = uitabgroup(main); tg.Layout.Row = 2;

S.ui.log = uitextarea(main,'Editable','off','FontName','Consolas','Value',{''}, ...
    'BackgroundColor',[1 1 1],'FontColor',[0 0 0]);
S.ui.log.Layout.Row = 3;

buildGeneratorTab(uitab(tg,'Title','Signal Generator'));
buildMotorTab(uitab(tg,'Title','XYZ Motors'));
buildScopeTab(uitab(tg,'Title','Oscilloscope'));
buildTraceTab(uitab(tg,'Title','Single Trace'));
buildZScanTab(uitab(tg,'Title','Z Echo Scan'));
buildEchoTab(uitab(tg,'Title','Echo Analysis'));
buildMaterialTab(uitab(tg,'Title','Material Analysis'));
buildXYScanTab(uitab(tg,'Title','XY Raster Scan'));
buildFreqSweepTab(uitab(tg,'Title','Freq Sweep (fixed XYZ)'));
buildXYAnalysisTab(uitab(tg,'Title','XY Analysis'));
buildSensTab(uitab(tg,'Title','Sensitivity / NEP'));
buildFreqTab(uitab(tg,'Title','FP Frequency Response'));

applyTheme();           % consistent fonts / colours across every control

%% ================================ SIGNAL GENERATOR TAB =================== %%
    function buildGeneratorTab(tab)
        g = uigridlayout(tab,[3 1]);
        g.RowHeight   = {60,'1x',60};
        g.ColumnWidth = {'1x'};

        c = uigridlayout(g,[1 5]); c.Layout.Row = 1;
        c.ColumnWidth = {70,'1x',95,95,30};
        uilabel(c,'Text','Resource:','HorizontalAlignment','right');
        S.ui.genIP = uieditfield(c,'text', ...
            'Value','USB0::0x1AB1::0x0647::DG5P272700184::0::INSTR');
        S.ui.genConnBtn = uibutton(c,'Text','Connect','ButtonPushedFcn',@genConnect);
        uibutton(c,'Text','Disconnect','ButtonPushedFcn',@(~,~)genDisconnect());
        S.ui.genLamp = uilamp(c,'Color',[0.6 0.6 0.6]);

        ch = uigridlayout(g,[1 2]); ch.Layout.Row = 2;
        ch.ColumnWidth = {'1x','1x'};
        S.ui.gc{1} = buildGenChannel(ch,1,defaultsCh(1),false);  % CH1: no idle level
        S.ui.gc{2} = buildGenChannel(ch,2,defaultsCh(2),true);   % CH2: has idle level

        b = uigridlayout(g,[1 3]); b.Layout.Row = 3;
        b.ColumnWidth = {'1x','1x',150};
        S.ui.out1 = uiswitch(b,'slider','Items',{'Out1 Off','Out1 On'}, ...
            'ValueChangedFcn',@(s,~)toggleOutput(1,s));
        S.ui.out2 = uiswitch(b,'slider','Items',{'Out2 Off','Out2 On'}, ...
            'ValueChangedFcn',@(s,~)toggleOutput(2,s));
        uibutton(b,'Text','Save settings','ButtonPushedFcn',@(~,~)quickSaveSettings());
    end

    function d = defaultsCh(n)
        if n==1
            d = struct('wave','SINE','freq',30e6,'amp',5,'phase',0,'offset',0, ...
                'burst','ON','cycles',10,'period',0.02,'delay',3.2e-6, ...
                'source','INT','idle','TOP');
        else
            d = struct('wave','SQUARE','freq',200e3,'amp',5,'phase',0,'offset',2.5, ...
                'burst','ON','cycles',1,'period',0.02,'delay',0, ...
                'source','INT','idle','TOP');
        end
    end

    function h = buildGenChannel(parent,ch,d,hasIdle)
        p = uipanel(parent,'Title',sprintf('Channel %d',ch));
        nrows = 12 + double(hasIdle);              % 11 fields + Apply (+ idle)
        gl = uigridlayout(p,[nrows 2]);
        gl.RowHeight   = repmat({26},1,nrows);
        gl.ColumnWidth = {120,'1x'};
        gl.Scrollable  = 'on';

        h.wave   = labeledDrop(gl,'Waveform',{'SINE','SQUARE','RAMP','PULSE'},d.wave);
        h.freq   = labeledNum (gl,'Frequency (Hz)',d.freq);
        h.amp    = labeledNum (gl,'Amplitude (Vpp)',d.amp);
        h.phase  = labeledNum (gl,'Phase (deg)',d.phase);
        h.offset = labeledNum (gl,'Offset (V)',d.offset);
        h.imp    = labeledDrop(gl,'Output load (Ohm)',{'High-Z','50','75','100'},'High-Z');
        h.burst  = labeledDrop(gl,'Burst',{'ON','OFF'},d.burst);
        h.cycles = labeledNum (gl,'Burst cycles',d.cycles);
        h.period = labeledNum (gl,'Burst period (s)',d.period);
        h.delay  = labeledNum (gl,'Delay (s)',d.delay);
        h.source = labeledDrop(gl,'Burst source',{'INT','BUS'},d.source);
        if hasIdle
            h.idle = labeledDrop(gl,'Idle level',{'TOP','BOTTOM','CENTER'},d.idle);
        end
        uibutton(gl,'Text',sprintf('Apply Channel %d',ch), ...
            'ButtonPushedFcn',@(~,~)applyGenChannel(ch));
    end

    function arg = impArg(v)                 % map dropdown -> setImpedance argument
        if strcmpi(v,'High-Z'); arg = 'INF'; else; arg = str2double(v); end
    end

    function applyGenChannel(ch)
        if ~requireGen(); return; end
        h = S.ui.gc{ch};
        step(sprintf('CH%d waveform',ch),  @()S.gen.setWaveform(ch,h.wave.Value));
        step(sprintf('CH%d output load',ch),@()S.gen.setImpedance(ch,impArg(h.imp.Value)));
        step(sprintf('CH%d frequency',ch), @()S.gen.setFrequency(ch,h.freq.Value));
        step(sprintf('CH%d amplitude',ch), @()S.gen.setAmplitude(ch,h.amp.Value));
        step(sprintf('CH%d phase',ch),     @()S.gen.setPhase(ch,h.phase.Value));
        step(sprintf('CH%d offset',ch),    @()S.gen.setOffset(ch,h.offset.Value));
        step(sprintf('CH%d burst state',ch),  @()S.gen.setBurstState(ch,h.burst.Value));
        if strcmp(h.burst.Value,'ON')
            step(sprintf('CH%d burst cycles',ch),@()S.gen.setBurstCycles(ch,h.cycles.Value));
            step(sprintf('CH%d burst period',ch),@()S.gen.setBurstPeriod(ch,h.period.Value));
            step(sprintf('CH%d delay',ch),       @()S.gen.setDelay(ch,h.delay.Value));
            step(sprintf('CH%d burst source',ch),@()S.gen.setBurstSource(ch,h.source.Value));
            if isfield(h,'idle')
                step(sprintf('CH%d idle level',ch),@()S.gen.setIdleLevel(ch,h.idle.Value));
            end
        end
        callGen(@()S.gen.alignPhase());            % align phase after the section
        logMsg('Channel %d configuration applied (phase aligned).',ch);
    end

    function toggleOutput(ch,sw)
        if ~requireGen(); revertSwitch(sw); return; end
        on = endsWith(sw.Value,'On');
        if on
            ok = safe(sprintf('output %d ON',ch), @()callGen(@()S.gen.outputOn(ch)));
        else
            ok = safe(sprintf('output %d OFF',ch),@()callGen(@()S.gen.outputOff(ch)));
        end
        if ok                                      % auto-align phase on every on AND off
            step('alignPhase (auto)', @()S.gen.alignPhase());
        else
            revertSwitch(sw);
        end
    end

    function genConnect(~,~)
        ok = safe('connect generator', @() doGenConnect());
        if ok; S.ui.genLamp.Color = [0 0.7 0]; S.ui.genConnBtn.Text = 'Reconnect';
        else;  S.ui.genLamp.Color = [0.85 0 0]; end
    end
    function doGenConnect()
        S.gen = DG5000Pro(S.ui.genIP.Value);
        S.gen.connect();
    end
    function genDisconnect()
        if isempty(S.gen); return; end
        try, S.gen.disconnect(); logMsg('OK : disconnect generator');
        catch e, logMsg('disconnect generator: %s',e.message); end
        S.gen = [];
        S.ui.genLamp.Color = [0.6 0.6 0.6];
        S.ui.genConnBtn.Text = 'Connect';
    end

%% ===================================== MOTOR TAB ======================== %%
    function buildMotorTab(tab)
        g = uigridlayout(tab,[2 3]);
        g.RowHeight   = {'1x',34};
        g.ColumnWidth = {'1x','1x','1x'};
        % parent, axis, serial, limit-from, limit-to, default offset
        buildMotorAxis(g,'X','0021550510',10, 15.3, 15);
        buildMotorAxis(g,'Y','0021550514',11, 15,   12);
        buildMotorAxis(g,'Z','0021550513', 0, 25,   17.5);
        sb = uibutton(g,'Text','Save settings','ButtonPushedFcn',@(~,~)quickSaveSettings());
        sb.Layout.Row = 2; sb.Layout.Column = [1 3];
    end

    function buildMotorAxis(parent,ax,serialDef,loDef,hiDef,offDef)
        p = uipanel(parent,'Title',sprintf('%s-Axis',ax));
        gl = uigridlayout(p,[9 2]);
        gl.RowHeight   = {28,28,28,28,54,28,28,28,28};
        gl.ColumnWidth = {120,'1x'};
        gl.Scrollable  = 'on';

        u.serial = labeledText(gl,'Serial number',serialDef);
        u.lo     = labeledNum (gl,'Limit from (mm)',loDef);
        u.hi     = labeledNum (gl,'Limit to (mm)',hiDef);
        u.off    = labeledNum (gl,'Move dist. from min (mm)',offDef);
        u.range  = card(gl,'Travel range','mm','%.2f'); u.range.panel.Layout.Column=[1 2];
        u.conn   = uibutton(gl,'Text','Connect','ButtonPushedFcn',@(~,~)motorConnect(ax));
        uibutton(gl,'Text','Get Range','ButtonPushedFcn',@(~,~)motorGetRange(ax));
        uibutton(gl,'Text','Move','ButtonPushedFcn',@(~,~)motorMove(ax));
        uibutton(gl,'Text','Disconnect','ButtonPushedFcn',@(~,~)motorDisconnect(ax));
        rb = uibutton(gl,'Text','Reference (FNL)','ButtonPushedFcn',@(~,~)motorReference(ax));
        rb.Layout.Column = [1 2];
        u.servo  = uiswitch(gl,'slider','Items',{'Servo Off','Servo On'}, ...
            'Value','Servo On','ValueChangedFcn',@(s,~)motorServo(ax,s));
        u.lamp   = uilamp(gl,'Color',[0.6 0.6 0.6]);
        S.ui.mot.(ax) = u;
    end

    function motorConnect(ax)
        u = S.ui.mot.(ax);
        serial = strtrim(u.serial.Value);
        if isempty(serial)
            alertUser('Enter the controller serial number for this axis first.','Connect');
            return;
        end
        try
            doMotorConnect(ax,serial);
            u.lamp.Color=[0 0.7 0]; u.conn.Text='Reconnect';
            logMsg('%s motor connected (SN %s).',ax,serial);
            motorGetRange(ax);
        catch e
            u.lamp.Color=[0.85 0 0];
            logMsg('connect %s motor: %s',ax,e.message);
            alertUser(sprintf([ ...
                'Could not open controller "%s" for the %s axis.\n\n' ...
                'PI driver says:\n%s\n\n' ...
                'Check, then press Connect again:\n' ...
                '  1. The controller is powered ON and its USB cable is connected.\n' ...
                '  2. No other program (PIMikroMove) or MATLAB session still has it open - ' ...
                'a controller allows only one connection at a time, so close/disconnect there first.\n' ...
                '  3. The serial number matches this axis''s controller (X, Y and Z each have ' ...
                'their own serial).'], serial, ax, e.message), 'Motor connection failed');
        end
    end
    function doMotorConnect(ax,serial)
        if ~isempty(S.motor.(ax))           % free any previous handle so the USB port is released
            try, S.motor.(ax).disconnect(); catch, end
            S.motor.(ax) = [];
        end
        m = PIMotorController(serial,'1');
        m.connect(); m.setServo(true);
        S.motor.(ax) = m;
    end

    function motorServo(ax,sw)
        if ~requireMotor(ax); revertSwitch(sw); return; end
        on = endsWith(sw.Value,'On');
        if ~safe(sprintf('%s servo',ax), @()S.motor.(ax).setServo(on)); revertSwitch(sw); end
    end

    function motorGetRange(ax)
        if ~requireMotor(ax); return; end
        safe(sprintf('%s travel range',ax), @() readRange(ax));
    end
    function readRange(ax)
        [mn,mx,~] = S.motor.(ax).getTravelRange();
        S.range.(ax) = [mn mx];
        S.ui.mot.(ax).range.val.Text = sprintf('%.2f - %.2f',mn,mx);
        logMsg('%s-axis travel range: %.2f mm to %.2f mm',ax,mn,mx);
    end

    function motorMove(ax)
        if ~requireMotor(ax); return; end
        u = S.ui.mot.(ax);
        lo = u.lo.Value; hi = u.hi.Value; off = u.off.Value;
        if off < lo || off > hi
            alertUser(sprintf('%s move distance must be between %g and %g mm.',ax,lo,hi),'Move blocked');
            return;
        end
        rng = S.range.(ax);
        if ~any(rng)
            alertUser('Read the travel range first (Get Range).','Move blocked'); return;
        end
        target = rng(1)+off;
        if target < rng(1) || target > rng(2)
            alertUser(sprintf('Target %.3f mm is outside hardware range %.2f..%.2f mm.', ...
                target,rng(1),rng(2)),'Move blocked'); return;
        end
        try
            if ~S.motor.(ax).isReferenced()
                alertUser(sprintf(['%s axis is not referenced yet. Press "Reference" ' ...
                    'first (the stage must home before absolute moves are allowed).'],ax), ...
                    'Move blocked'); return;
            end
        catch
            % isReferenced unavailable/not ready - let the move attempt surface any error
        end
        safe(sprintf('move %s to %.3f mm',ax,target), @()motorDoMove(ax,target));
    end

    function motorDoMove(ax,target)
        try, S.motor.(ax).setServo(true); catch, end   % ensure servo is on
        S.motor.(ax).moveAbs(target);
    end

    function motorMoveRetry(ax,target,tries)
        if nargin < 3; tries = 3; end
        lastErr = [];
        for k = 1:tries
            try
                S.motor.(ax).moveAbs(target); return;     % success
            catch e
                lastErr = e;
                logMsg('move %s retry %d/%d after: %s', ax, k, tries, e.message);
                pause(0.4);
                try, S.motor.(ax).setServo(true); catch, end   % re-assert servo and retry
            end
        end
        rethrow(lastErr);
    end

    function motorReference(ax)
        if ~requireMotor(ax); return; end
        m = S.motor.(ax); u = S.ui.mot.(ax);
        try, m.setServo(true); u.servo.Value = 'Servo On'; catch, end
        meth = 'FNL';                           % reference to the negative limit
        if safe(sprintf('reference %s axis (%s)',ax,meth), @() m.reference(meth))
            logMsg('%s axis referenced (%s); position now %.4f mm.', ...
                ax, meth, m.getPosition());
            motorGetRange(ax);                  % travel limits are valid once referenced
        end
    end

    function motorDisconnect(ax)
        if isempty(S.motor.(ax)); return; end
        safe(sprintf('disconnect %s motor',ax), @()S.motor.(ax).disconnect());
        S.motor.(ax) = [];
        S.ui.mot.(ax).lamp.Color = [0.6 0.6 0.6];
        S.ui.mot.(ax).conn.Text  = 'Connect';
    end

%% ================================== OSCILLOSCOPE TAB ==================== %%
    function buildScopeTab(tab)
        g = uigridlayout(tab,[3 1]);
        g.RowHeight = {60,'1x',64}; g.ColumnWidth = {'1x'};

        c = uigridlayout(g,[1 7]); c.Layout.Row = 1;
        c.ColumnWidth = {70,'1x',120,80,90,90,30};
        uilabel(c,'Text','IP:','HorizontalAlignment','right');
        S.ui.oscIP   = uieditfield(c,'text','Value','10.48.7.251');
        S.ui.oscBuf  = uieditfield(c,'numeric','Value',2^22,'ValueDisplayFormat','%g');
        S.ui.oscTout = uieditfield(c,'numeric','Value',60);
        S.ui.oscConn = uibutton(c,'Text','Connect','ButtonPushedFcn',@scopeConnect);
        uibutton(c,'Text','Disconnect','ButtonPushedFcn',@(~,~)scopeDisconnect());
        S.ui.oscLamp = uilamp(c,'Color',[0.6 0.6 0.6]);

        s = uigridlayout(g,[19 2]); s.Layout.Row = 2;
        s.RowHeight   = repmat({26},1,19);
        s.ColumnWidth = {200,'1x'};
        s.Scrollable  = 'on';
        o.tscale = labeledNum (s,'Time scale (s/div)',10e-6);
        o.ndiv   = labeledNum (s,'Number of divisions',10);
        o.acq    = labeledDrop(s,'Acquisition type',{'NORM','PEAK','AVER'},'NORM');
        o.trigT  = labeledDrop(s,'Trigger type',{'EDGE'},'EDGE');
        o.trigL  = labeledNum (s,'Trigger level (V)',75e-3);
        o.imp1   = labeledDrop(s,'CH1 impedance',{'FIFT','ONEM'},'FIFT');
        o.imp2   = labeledDrop(s,'CH2 impedance',{'FIFT','ONEM'},'FIFT');
        o.imp3   = labeledDrop(s,'CH3 impedance',{'FIFT','ONEM'},'FIFT');
        o.imp4   = labeledDrop(s,'CH4 impedance',{'FIFT','ONEM'},'FIFT');
        o.vs1    = labeledNum (s,'CH1 vertical scale (V/div)',1);
        o.vs2    = labeledNum (s,'CH2 vertical scale (V/div)',200e-3);
        o.vs3    = labeledNum (s,'CH3 vertical scale (V/div)',1);
        o.vs4    = labeledNum (s,'CH4 vertical scale (V/div)',1);
        o.off1   = labeledNum (s,'CH1 offset (V)',0);
        o.off2   = labeledNum (s,'CH2 offset (V)',0);
        o.off3   = labeledNum (s,'CH3 offset (V)',0);
        o.off4   = labeledNum (s,'CH4 offset (V)',0);
        ab = uibutton(s,'Text','Apply Settings','ButtonPushedFcn',@(~,~)applyScope());
        ab.Layout.Column = [1 2];
        sb = uibutton(s,'Text','Save settings','ButtonPushedFcn',@(~,~)quickSaveSettings());
        sb.Layout.Column = [1 2];
        S.ui.osc = o;

        b = uigridlayout(g,[1 2]); b.Layout.Row = 3;
        b.ColumnWidth = {160,'1x'};
        uibutton(b,'Text','Read Sample Rate','ButtonPushedFcn',@(~,~)readSampleRate());
        S.ui.oscFs = card(b,'Sample rate','MSa/s','%.2f');
    end

    function scopeConnect(~,~)
        ok = safe('connect oscilloscope', @() doScopeConnect());
        if ok; S.ui.oscLamp.Color=[0 0.7 0]; S.ui.oscConn.Text='Reconnect';
        else;  S.ui.oscLamp.Color=[0.85 0 0]; end
    end
    function doScopeConnect()
        S.osc = T3DSO2502A(S.ui.oscIP.Value);
        S.osc.setInputBufferSize(S.ui.oscBuf.Value);
        S.osc.setTimeout(S.ui.oscTout.Value);
        S.osc.connect();
    end
    function scopeDisconnect()
        if isempty(S.osc); return; end
        try, S.osc.disconnect(); logMsg('OK : disconnect oscilloscope');
        catch e, logMsg('disconnect oscilloscope: %s',e.message); end
        S.osc = [];
        S.ui.oscLamp.Color = [0.6 0.6 0.6];
        S.ui.oscConn.Text = 'Connect';
    end

    function applyScope()
        if ~requireScope(); return; end
        o = S.ui.osc;
        total = o.tscale.Value*o.ndiv.Value;
        step('time scale',     @()S.osc.setTimeScale(o.tscale.Value));
        step('timebase delay', @()S.osc.setTimebaseDelay(-total/2));
        step('acquisition type',@()S.osc.setAcquisitionType(o.acq.Value));
        step('trigger type',   @()S.osc.setTriggerType(o.trigT.Value));
        step('trigger level',  @()S.osc.setTriggerLevel(o.trigL.Value));
        imps = {o.imp1.Value,o.imp2.Value,o.imp3.Value,o.imp4.Value};
        vss  = [o.vs1.Value, o.vs2.Value, o.vs3.Value, o.vs4.Value];
        offs = [o.off1.Value,o.off2.Value,o.off3.Value,o.off4.Value];
        for chn = 1:4
            step(sprintf('CH%d impedance',chn),     @()S.osc.setImpedance(chn,imps{chn}));
            step(sprintf('CH%d vertical scale',chn),@()S.osc.setVerticalScale(chn,vss(chn)));
            step(sprintf('CH%d offset',chn),        @()S.osc.setOffset(chn,offs(chn)));
        end
        logMsg('Oscilloscope settings applied (span = %.3g s).',total);
        readSampleRate();
    end

    function readSampleRate()
        if ~requireScope(); return; end
        safe('read sample rate', @() showFs());
    end
    function showFs()
        fs = S.osc.getSampleRate();
        S.fsActual = fs;
        setCard(S.ui.oscFs, fs/1e6);
        logMsg('Oscilloscope sample rate: %.2f MSa/s',fs/1e6);
    end

%% ================================ Z ECHO SCAN TAB ======================= %%
%% ============================== SINGLE TRACE TAB ======================= %%
    function buildTraceTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {360,'1x'};

        pL = uipanel(g,'Title','Single trace (acquire one & save, no motion)');
        gL = uigridlayout(pL,[14 2]);
        gL.RowHeight   = repmat({26},1,14);
        gL.ColumnWidth = {185,'1x'};
        gL.Scrollable  = 'on';

        tr.method  = labeledDrop(gL,'Method',{'getDataAveraged','getData'},'getDataAveraged');
        tr.channel = labeledNum (gL,'Channel',2);
        tr.conv    = labeledDrop(gL,'conversion (getData)',{'true','false'},'true');
        tr.adc     = labeledNum (gL,'adcMaxValue (2^16)',2^16);
        tr.resetCh = labeledNum (gL,'Reset averaging channel',1);
        tr.zeroOff = labeledDrop(gL,'Zero CH offset first',{'Yes','No'},'Yes');
        tr.pause   = labeledNum (gL,'Pause before acquire (s)',0);

        tr.base = labeledText(gL,'Base folder',pwd);
        tr.date = labeledText(gL,'Date folder',datestr(now,'yyyy-mm-dd'));
        tr.file = labeledText(gL,'File name (.mat)','sample01_trace.mat');
        srow = uigridlayout(gL,[1 2]); srow.Layout.Column=[1 2]; srow.Padding=[0 0 0 0];
        srow.ColumnWidth = {'1x','1x'};
        uibutton(srow,'Text','Browse folder...','ButtonPushedFcn',@(~,~)browseInto('tr'));
        uibutton(srow,'Text','Save .mat now','ButtonPushedFcn',@(~,~)traceSave());

        tr.prog = uilabel(gL,'Text','Idle.'); tr.prog.Layout.Column=[1 2];
        ab = uibutton(gL,'Text','Acquire Trace','BackgroundColor',[0.2 0.6 0.2], ...
            'FontColor','w','ButtonPushedFcn',@(~,~)traceAcquire());
        ab.Layout.Column = [1 2];
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[2 1]); pR.RowHeight = {'1x',28};
        tr.ax = uiaxes(pR); tr.ax.Layout.Row = 1;
        title(tr.ax,'Acquired trace appears here');
        xlabel(tr.ax,'Time (us)'); ylabel(tr.ax,'Amplitude');
        rr = uigridlayout(pR,[1 2]); rr.Layout.Row = 2; rr.ColumnWidth = {'1x','1x'};
        uibutton(rr,'Text','Plot raw','ButtonPushedFcn',@(~,~)tracePlot(false));
        uibutton(rr,'Text','Plot offset-removed','ButtonPushedFcn',@(~,~)tracePlot(true));

        S.ui.tr = tr;
        refreshTraceAcqEnables();
        tr.method.ValueChangedFcn = @(~,~)refreshTraceAcqEnables();
    end

    function refreshTraceAcqEnables()
        tr = S.ui.tr;
        isAvg = strcmp(tr.method.Value,'getDataAveraged');
        tr.resetCh.Enable = onoff(isAvg);
        tr.conv.Enable    = onoff(~isAvg);
    end

    function traceAcquire()
        if ~requireScope(); return; end
        tr = S.ui.tr;
        cfg.method  = tr.method.Value;
        cfg.channel = tr.channel.Value;
        cfg.conv    = strcmp(tr.conv.Value,'true');
        cfg.adc     = tr.adc.Value;

        if isempty(S.fsActual) || S.fsActual <= 0
            try, S.fsActual = S.osc.getSampleRate(); catch, S.fsActual = []; end
        end
        if strcmp(tr.zeroOff.Value,'Yes')
            safe(sprintf('zero CH%d offset',cfg.channel), @()S.osc.setOffset(cfg.channel,0));
        end
        if strcmp(cfg.method,'getDataAveraged')
            safe('reset averaging', @()S.osc.resetAveragingByOffset(tr.resetCh.Value));
        end
        if tr.pause.Value > 0; pause(tr.pause.Value); end

        ok = safe('acquire trace', @()doTraceAcquire(cfg));
        if ~ok; tr.prog.Text = 'Acquire failed - see log.'; return; end
        tr.prog.Text = sprintf('Acquired CH%d: %d samples.', cfg.channel, numel(S.strace.data));
        logMsg('Single trace: CH%d, %d samples (%s).', cfg.channel, numel(S.strace.data), cfg.method);
        tracePlot(false);
    end
    function doTraceAcquire(cfg)
        [data, t] = acquireTrace(cfg, []);
        S.strace = struct('data',data,'t',t,'channel',cfg.channel);
    end

    function tracePlot(removeOffset)
        if isempty(S.strace); alertUser('Acquire a trace first.','Plot'); return; end
        tr = S.ui.tr; d = S.strace.data(:); t = S.strace.t(:);
        if removeOffset; d = d - mean(d); end
        cla(tr.ax); plot(tr.ax, t*1e6, d, 'LineWidth', 1); grid(tr.ax,'on');
        ttl = sprintf('CH%d single trace (%d samples)', S.strace.channel, numel(d));
        if removeOffset; ttl = [ttl '  - offset removed']; end
        title(tr.ax, ttl);
        xlabel(tr.ax,'Time (us)'); ylabel(tr.ax,'Amplitude');
    end

    function traceSave()
        if isempty(S.strace); alertUser('Acquire a trace first.','Save'); return; end
        tr = S.ui.tr;
        folder = fullfile(tr.base.Value, tr.date.Value);
        if ~exist(folder,'dir')
            if ~safe('create folder', @()mkdir(folder)); return; end
        end
        fname = fullfile(folder, ensureMat(tr.file.Value));
        data = S.strace.data; t = S.strace.t; data_all = {S.strace.data}; %#ok<NASGU>
        try
            save(fname,'data','t','data_all','-v7.3');
        catch e
            alertUser(sprintf('Could not save the file:\n%s',e.message),'Save .mat');
            logMsg('save .mat: %s', e.message); return;
        end
        tr.prog.Text = sprintf('Saved -> %s', fname);
        logMsg('Saved single trace -> %s', fname);
    end

    function buildZScanTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {360,'1x'};

        pL = uipanel(g,'Title','Z scan (acquire & save)');
        gL = uigridlayout(pL,[18 2]);
        gL.RowHeight   = repmat({26},1,18);
        gL.ColumnWidth = {175,'1x'};
        gL.Scrollable  = 'on';

        z.step    = labeledNum (gL,'Step size (mm)',0.1);
        z.length  = labeledNum (gL,'Scan length (mm)',1);
        z.dir     = labeledDrop(gL,'Direction',{'Down (+)','Up (-)'},'Down (+)');
        z.settle  = labeledNum (gL,'Settle after move (s)',50);
        z.post    = labeledNum (gL,'Pause after acquire (s)',1);

        z.method  = labeledDrop(gL,'Method',{'getDataAveraged','getData'},'getDataAveraged');
        z.channel = labeledNum (gL,'Channel',2);
        z.conv    = labeledDrop(gL,'conversion (getData)',{'true','false'},'true');
        z.adc     = labeledNum (gL,'adcMaxValue (2^16)',2^16);
        z.resetCh = labeledNum (gL,'Reset averaging channel',1);

        z.base = labeledText(gL,'Base folder',pwd);
        z.date = labeledText(gL,'Date folder',datestr(now,'yyyy-mm-dd'));
        z.file = labeledText(gL,'File name (.mat)','sample01_zscan.mat');
        srow = uigridlayout(gL,[1 2]); srow.Layout.Column=[1 2]; srow.Padding=[0 0 0 0];
        srow.ColumnWidth = {'1x','1x'};
        uibutton(srow,'Text','Browse folder...','ButtonPushedFcn',@(~,~)browseInto('z'));
        uibutton(srow,'Text','Save .mat now','ButtonPushedFcn',@(~,~)zSave());

        z.prog = uilabel(gL,'Text','Idle.'); z.prog.Layout.Column=[1 2];
        brow = uigridlayout(gL,[1 2]); brow.Layout.Column=[1 2]; brow.Padding=[0 0 0 0];
        brow.ColumnWidth = {'1x','1x'};
        z.runBtn  = uibutton(brow,'Text','Run Z Scan','BackgroundColor',[0.2 0.6 0.2], ...
            'FontColor','w','ButtonPushedFcn',@(~,~)runZScan());
        z.stopBtn = uibutton(brow,'Text','Stop','BackgroundColor',[0.7 0.2 0.2], ...
            'FontColor','w','ButtonPushedFcn',@(~,~)stopScanReq());
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[2 1]); pR.RowHeight = {'1x',28};
        z.ax = uiaxes(pR); z.ax.Layout.Row = 1;
        title(z.ax,'Raw traces appear here after a scan');
        xlabel(z.ax,'Time (us)'); ylabel(z.ax,'Amplitude');
        rr = uigridlayout(pR,[1 3]); rr.Layout.Row = 2; rr.ColumnWidth = {'1x',120,120};
        z.sel = uidropdown(rr,'Items',{'(no scan yet)'},'Enable','off', ...
            'ValueChangedFcn',@(~,~)plotZRawSelected());
        uibutton(rr,'Text','Plot Selected','ButtonPushedFcn',@(~,~)plotZRawSelected());
        uibutton(rr,'Text','Plot All','ButtonPushedFcn',@(~,~)plotZRawAll());

        S.ui.z = z;
        refreshZAcqEnables();
        z.method.ValueChangedFcn = @(~,~)refreshZAcqEnables();
    end

    function refreshZAcqEnables()
        z = S.ui.z;
        isAvg = strcmp(z.method.Value,'getDataAveraged');
        z.resetCh.Enable = onoff(isAvg);
        z.conv.Enable    = onoff(~isAvg);
    end

    function stopScanReq()
        S.stopScan = true;
        logMsg('Stop requested - finishing current point...');
    end

    function runZScan()
        if ~requireScope(); return; end
        if ~requireMotor('Z'); return; end
        z = S.ui.z;

        stepMM  = abs(z.step.Value);
        scanLen = abs(z.length.Value);
        sgn     = 1; if startsWith(z.dir.Value,'Up'); sgn = -1; end
        offs    = 0:stepMM:scanLen;            % inclusive, like your xy grid
        nSteps  = numel(offs);

        cfg.method  = z.method.Value;
        cfg.channel = z.channel.Value;
        cfg.conv    = strcmp(z.conv.Value,'true');
        cfg.adc     = z.adc.Value;

        if isempty(S.fsActual) || S.fsActual <= 0
            try, S.fsActual = S.osc.getSampleRate(); catch, S.fsActual = []; end
        end

        safe(sprintf('zero CH%d offset',cfg.channel), @()S.osc.setOffset(cfg.channel,0));

        try, pos_z = S.motor.Z.getPosition();
        catch, pos_z = S.range.Z(1) + off_fallback(); end

        positions_mm = zeros(1,nSteps);
        data_all = cell(1,nSteps);
        t = [];
        S.stopScan = false; z.runBtn.Enable = 'off';
        cleaner = onCleanup(@()set(z.runBtn,'Enable','on')); %#ok<NASGU>
        logMsg('Z scan: %d steps of %.4f mm (length %.3f mm).', nSteps, stepMM, scanLen);

        nDone = 0;
        try
            for i = 1:nSteps
                if S.stopScan; break; end
                target = pos_z + sgn*offs(i);
                motorMoveRetry('Z',target);
                if strcmp(cfg.method,'getDataAveraged')
                    S.osc.resetAveragingByOffset(z.resetCh.Value);
                end
                interruptiblePause(z.settle.Value);
                if S.stopScan; break; end

                try, current = S.motor.Z.getPosition(); catch, current = target; end
                positions_mm(i) = current;

                [data, t] = acquireTrace(cfg, t);
                data_all{i} = data; nDone = i;

                z.prog.Text = sprintf('Step %d of %d   Z=%.4f mm', i, nSteps, current);
                logMsg('Z step %d/%d: Z=%.4f mm (%d samples)', i, nSteps, current, numel(data));
                drawnow limitrate;
                interruptiblePause(z.post.Value);
            end
        catch e
            logMsg('Z SCAN ERROR: %s', e.message);
            if contains(e.message,'FTDIUSB','IgnoreCase',true) || ...
               contains(e.message,'IO error','IgnoreCase',true)
                alertUser(sprintf([ ...
                    'The USB link to the Z controller dropped during the scan (FTDIUSB IO error).\n\n' ...
                    'This is a communication dropout, not a settings problem. Try:\n' ...
                    '  - reseat or replace the USB cable; use a direct port, avoid USB hubs\n' ...
                    '  - make sure only this program is talking to the controller\n' ...
                    '  - reconnect the Z motor, then run the scan again\n\n' ...
                    'Partial data up to step %d was kept and saved.'], nDone), 'Z scan - USB error');
            else
                alertUser(e.message,'Z scan error');
            end
        end

        positions_mm = positions_mm(1:nDone);
        data_all     = data_all(1:nDone);
        if nDone == 0; z.prog.Text = 'No data acquired.'; return; end

        S.zscan = struct('positions_mm',positions_mm,'data_all',{data_all},'t',t);
        S.zres  = [];                         % invalidate any old analysis
        refreshZSel();
        plotZRawAll();
        if ~isempty(strtrim(z.file.Value)); zSave(); end   % auto-save raw data
        if S.stopScan; z.prog.Text = sprintf('Stopped after %d steps (saved).', nDone);
        else;          z.prog.Text = sprintf('Done: %d steps (saved). Now use Echo Analysis.', nDone); end
    end

    function v = off_fallback()
        v = S.ui.mot.Z.off.Value;
    end

    function [data, t] = acquireTrace(cfg, t)
        switch cfg.method
            case 'getDataAveraged'
                data = S.osc.getDataAveraged(cfg.channel, 1, cfg.adc);
            case 'getData'
                data = S.osc.getData(cfg.channel, cfg.conv, cfg.adc);
        end
        data = data(:);
        if isempty(t)
            N = numel(data);
            if ~isempty(S.fsActual) && S.fsActual > 0
                dt = 1/(S.fsActual/2);        % matches acquire_single_trace
            else
                dt = 1; logMsg('WARN: no sample rate; t is sample index.');
            end
            t = ((0:N-1)*dt).';
        else
            t = t(:);
        end
    end

    function zSave()
        if isempty(S.zscan); alertUser('Run a Z scan first.','Save'); return; end
        z = S.ui.z;
        folder = fullfile(z.base.Value, z.date.Value);
        if ~exist(folder,'dir')
            if ~safe('create folder', @()mkdir(folder)); return; end
        end
        fname = fullfile(folder, ensureMat(z.file.Value));
        data_all = S.zscan.data_all; t = S.zscan.t; positions_mm = S.zscan.positions_mm;
        try
            save(fname,'data_all','t','positions_mm','-v7.3');
        catch e
            alertUser(sprintf('Could not save the file:\n%s',e.message),'Save .mat');
            logMsg('save .mat: %s', e.message); return;
        end
        S.zscan.savedTo = fname;
        logMsg('Saved %d traces -> %s', numel(data_all), fname);
    end

    function refreshZSel()
        if isempty(S.zscan); return; end
        Z = S.zscan; n = numel(Z.data_all);
        items = arrayfun(@(k)sprintf('step %d | Z=%.4f mm',k,Z.positions_mm(k)), ...
            1:n,'UniformOutput',false);
        S.ui.z.sel.Items = items; S.ui.z.sel.Enable='on'; S.ui.z.sel.Value=items{1};
        S.ui.a.sel.Items = items; S.ui.a.sel.Enable='on'; S.ui.a.sel.Value=items{1};
        configTraceSlider(n);
    end

    function configTraceSlider(n)
        a = S.ui.a;
        if n >= 2
            a.slider.Limits = [1 n];
            a.slider.MajorTicks = unique(round(linspace(1,n,min(n,8))));
            a.slider.Value = 1; a.slider.Enable = 'on';
        else
            a.slider.Limits = [1 2]; a.slider.Value = 1; a.slider.Enable = 'off';
        end
        a.sliderVal.Text = '1';
    end

    function sliderTrace(val)
        if isempty(S.zscan); return; end
        items = S.ui.a.sel.Items; n = numel(items);
        k = max(1,min(n,round(val)));
        S.ui.a.sliderVal.Text = sprintf('%d',k);
        if k <= numel(items); S.ui.a.sel.Value = items{k}; end
        plotEchoSelected();
    end

    function plotZRawSelected()
        if isempty(S.zscan); return; end
        z=S.ui.z; Z=S.zscan;
        k=find(strcmp(z.sel.Items,z.sel.Value),1); if isempty(k); k=1; end
        cla(z.ax); plot(z.ax, Z.t*1e6, zoff(Z.data_all{k}),'b');
        title(z.ax,sprintf('Amplitude vs time  |  Z=%.4f mm  (step %d)',Z.positions_mm(k),k));
        xlabel(z.ax,'Time (us)'); ylabel(z.ax,'Amplitude (offset removed)');
    end
    function plotZRawAll()
        if isempty(S.zscan); return; end
        z=S.ui.z; Z=S.zscan; cla(z.ax); hold(z.ax,'on');
        for k=1:numel(Z.data_all)
            plot(z.ax, Z.t*1e6, zoff(Z.data_all{k}),'Color',[0.55 0.55 0.55 0.5]);
        end
        hold(z.ax,'off');
        title(z.ax,sprintf('All %d traces - amplitude vs time',numel(Z.data_all)));
        xlabel(z.ax,'Time (us)'); ylabel(z.ax,'Amplitude (offset removed)');
    end

%% ============================== XY RASTER SCAN TAB ===================== %%
    function buildXYScanTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {360,'1x'};

        pL = uipanel(g,'Title','XY raster scan (acquire & save)');
        gL = uigridlayout(pL,[19 2]);
        gL.RowHeight   = repmat({26},1,19);
        gL.ColumnWidth = {175,'1x'};
        gL.Scrollable  = 'on';

        x.step    = labeledNum (gL,'Step size (mm)',0.1);
        x.length  = labeledNum (gL,'Scan length (mm)',1);
        x.settleY = labeledNum (gL,'Settle after Y move (s)',2);
        x.settleX = labeledNum (gL,'Reset+wait after X move (s)',20);

        x.zmove = labeledDrop(gL,'Move Z at start',{'Yes','No'},'Yes');
        x.zpos  = labeledNum (gL,'Fixed Z position (mm)',0);
        wideButton(gL,'Use current Z position',@(~,~)xyUseCurrentZ());

        x.method  = labeledDrop(gL,'Method',{'getDataAveraged','getData'},'getDataAveraged');
        x.channel = labeledNum (gL,'Channel',2);
        x.conv    = labeledDrop(gL,'conversion (getData)',{'true','false'},'true');
        x.adc     = labeledNum (gL,'adcMaxValue (2^16)',2^16);
        x.resetCh = labeledNum (gL,'Reset averaging channel',2);

        x.base = labeledText(gL,'Base folder',pwd);
        x.date = labeledText(gL,'Date folder',datestr(now,'yyyy-mm-dd'));
        x.file = labeledText(gL,'File name (.mat)','full_scan_xy_1.mat');
        srow = uigridlayout(gL,[1 2]); srow.Layout.Column=[1 2]; srow.Padding=[0 0 0 0];
        srow.ColumnWidth = {'1x','1x'};
        uibutton(srow,'Text','Browse folder...','ButtonPushedFcn',@(~,~)browseInto('x'));
        uibutton(srow,'Text','Save .mat now','ButtonPushedFcn',@(~,~)xySave());

        x.prog = uilabel(gL,'Text','Idle.'); x.prog.Layout.Column=[1 2];
        brow = uigridlayout(gL,[1 2]); brow.Layout.Column=[1 2]; brow.Padding=[0 0 0 0];
        brow.ColumnWidth = {'1x','1x'};
        x.runBtn  = uibutton(brow,'Text','Run XY Scan','ButtonPushedFcn',@(~,~)runXYScan());
        x.stopBtn = uibutton(brow,'Text','Stop','ButtonPushedFcn',@(~,~)stopScanReq());
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[3 1]); pR.RowHeight = {66,'1x',28};
        crow = uigridlayout(pR,[1 2]); crow.Layout.Row=1; crow.ColumnWidth={'1x','1x'};
        x.cardGrid = card(crow,'Grid (X x Y)','','%s');
        x.cardPts  = card(crow,'Points done','','%d');
        x.ax = uiaxes(pR); x.ax.Layout.Row=2;
        title(x.ax,'C-scan amplitude map appears here');
        xlabel(x.ax,'X (mm)'); ylabel(x.ax,'Y (mm)');
        rr = uigridlayout(pR,[1 1]); rr.Layout.Row=3;
        uibutton(rr,'Text','Plot amplitude map','ButtonPushedFcn',@(~,~)plotXYMap());

        S.ui.x = x;
        refreshXYEnables();
        x.method.ValueChangedFcn = @(~,~)refreshXYEnables();
        x.zmove.ValueChangedFcn  = @(~,~)refreshXYEnables();
    end

    function refreshXYEnables()
        x = S.ui.x; isAvg = strcmp(x.method.Value,'getDataAveraged');
        x.resetCh.Enable = onoff(isAvg);
        x.conv.Enable    = onoff(~isAvg);
        x.zpos.Enable    = onoff(strcmp(x.zmove.Value,'Yes'));
    end

    function xyUseCurrentZ()
        if ~requireMotor('Z'); return; end
        try
            S.ui.x.zpos.Value = S.motor.Z.getPosition();
            logMsg('Fixed Z set to current position %.4f mm.', S.ui.x.zpos.Value);
        catch e
            alertUser(e.message,'Read Z position');
        end
    end

    function runXYScan()
        if ~requireScope(); return; end
        if ~requireMotor('X') || ~requireMotor('Y'); return; end
        x = S.ui.x;

        % move Z to the fixed value and hold it there for the whole scan
        zPos = NaN;
        if strcmp(x.zmove.Value,'Yes')
            if ~requireMotor('Z'); return; end
            zPos = x.zpos.Value;
            if any(S.range.Z) && (zPos < S.range.Z(1) || zPos > S.range.Z(2))
                alertUser(sprintf('Z=%.3f mm is outside the Z travel range %.2f..%.2f mm.', ...
                    zPos,S.range.Z(1),S.range.Z(2)),'Scan blocked'); return;
            end
            if ~safe(sprintf('move Z to %.3f mm',zPos), @()S.motor.Z.moveAbs(zPos)); return; end
            interruptiblePause(x.settleY.Value);
        else
            try, zPos = S.motor.Z.getPosition(); catch, zPos = NaN; end
        end

        stepMM  = abs(x.step.Value);
        scanLen = abs(x.length.Value);
        half    = scanLen/2;

        % centre on the current X/Y positions (fallback: range min + offset)
        try, cx = S.motor.X.getPosition(); catch, cx = S.range.X(1)+S.ui.mot.X.off.Value; end
        try, cy = S.motor.Y.getPosition(); catch, cy = S.range.Y(1)+S.ui.mot.Y.off.Value; end
        xPositions = cx + (-half:stepMM:half);
        yPositions = cy + (-half:stepMM:half);
        numX = numel(xPositions); numY = numel(yPositions);

        % keep inside hardware travel if ranges are known
        if any(S.range.X) && (min(xPositions)<S.range.X(1) || max(xPositions)>S.range.X(2)) || ...
           any(S.range.Y) && (min(yPositions)<S.range.Y(1) || max(yPositions)>S.range.Y(2))
            alertUser('Scan grid falls outside the motor travel range.','Scan blocked'); return;
        end

        cfg.method  = x.method.Value;
        cfg.channel = x.channel.Value;
        cfg.conv    = strcmp(x.conv.Value,'true');
        cfg.adc     = x.adc.Value;
        if isempty(S.fsActual) || S.fsActual<=0
            try, S.fsActual = S.osc.getSampleRate(); catch, S.fsActual = []; end
        end

        allData = cell(numY,numX); allX = zeros(numY,numX); allY = zeros(numY,numX);
        t = []; S.stopScan = false; x.runBtn.Enable = 'off';
        cleaner = onCleanup(@()set(x.runBtn,'Enable','on')); %#ok<NASGU>
        x.cardGrid.val.Text = sprintf('%d x %d',numX,numY);
        setCard(x.cardPts,0);
        logMsg('XY scan: %d x %d = %d points.',numX,numY,numX*numY);

        done = 0;
        try
            for i = 1:numY
                if S.stopScan; break; end
                currentY = yPositions(i);
                motorMoveRetry('Y',currentY);
                interruptiblePause(x.settleY.Value);
                for j = 1:numX
                    if S.stopScan; break; end
                    currentX = xPositions(j);
                    motorMoveRetry('X',currentX);
                    if strcmp(cfg.method,'getDataAveraged')
                        S.osc.resetAveragingByOffset(x.resetCh.Value);
                    end
                    interruptiblePause(x.settleX.Value);
                    if S.stopScan; break; end

                    [data,t] = acquireTrace(cfg,t);
                    allData{i,j} = data; allX(i,j) = currentX; allY(i,j) = currentY;
                    done = done+1;
                    x.prog.Text = sprintf('Point [%d,%d]  X=%.3f  Y=%.3f',i,j,currentX,currentY);
                    setCard(x.cardPts,done);
                    logMsg('Point [%d,%d] saved: X=%.3f, Y=%.3f',i,j,currentX,currentY);
                    drawnow limitrate;
                end
            end
        catch e
            logMsg('XY SCAN ERROR: %s',e.message); alertUser(e.message,'XY scan error');
        end

        S.xyscan = struct('allData',{allData},'allX',allX,'allY',allY,'t',t, ...
            'xPositions',xPositions,'yPositions',yPositions,'zPos',zPos);
        if ~isempty(strtrim(x.file.Value)); xySave(); end
        plotXYMap();
        if S.stopScan; x.prog.Text = sprintf('Stopped (%d points, saved).',done);
        else;          x.prog.Text = sprintf('Done: %d points (saved).',done); end
    end

    function xySave()
        if isempty(S.xyscan); alertUser('Run an XY scan first.','Save'); return; end
        x = S.ui.x;
        folder = fullfile(x.base.Value, x.date.Value);
        if ~exist(folder,'dir')
            if ~safe('create folder', @()mkdir(folder)); return; end
        end
        fname = fullfile(folder, ensureMat(x.file.Value));
        allData = S.xyscan.allData; t = S.xyscan.t;
        allX = S.xyscan.allX; allY = S.xyscan.allY; zPos = S.xyscan.zPos;
        try
            save(fname,'allData','t','allX','allY','zPos','-v7.3');
        catch e
            alertUser(sprintf('Could not save the file:\n%s',e.message),'Save .mat');
            logMsg('save .mat: %s', e.message); return;
        end
        logMsg('Saved XY scan -> %s', fname);
    end

    function plotXYMap()
        if isempty(S.xyscan); alertUser('Run an XY scan first.','Map'); return; end
        X = S.xyscan; [numY,numX] = size(X.allData);
        amp = nan(numY,numX);
        for i = 1:numY
            for j = 1:numX
                d = X.allData{i,j};
                if ~isempty(d); d = d(:); amp(i,j) = max(abs(d-mean(d))); end
            end
        end
        ax = S.ui.x.ax; cla(ax); ax.XLimMode='auto'; ax.YLimMode='auto';
        imagesc(ax, X.xPositions, X.yPositions, amp);
        axis(ax,'xy'); axis(ax,'tight'); colorbar(ax);
        title(ax,'C-scan: peak amplitude (offset removed)');
        xlabel(ax,'X (mm)'); ylabel(ax,'Y (mm)');
    end
%% ========================= GENERATOR FREQ SWEEP TAB =================== %%
    function buildFreqSweepTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {360,'1x'};

        pL = uipanel(g,'Title','Generator frequency sweep (fixed XYZ position)');
        gL = uigridlayout(pL,[21 2]);
        gL.RowHeight   = repmat({26},1,21);
        gL.ColumnWidth = {185,'1x'};
        gL.Scrollable  = 'on';

        q.genCh   = labeledNum (gL,'Generator channel',1);
        q.fStart  = labeledNum (gL,'Start freq (MHz)',2);
        q.fStop   = labeledNum (gL,'Stop freq (MHz)',20);
        q.fStep   = labeledNum (gL,'Step (MHz)',0.5);
        q.settle  = labeledNum (gL,'Settle after set freq (s)',0.5);
        q.post    = labeledNum (gL,'Pause after acquire (s)',0);
        q.outOn   = labeledDrop(gL,'Ensure output ON',{'Yes','No'},'Yes');
        q.align   = labeledDrop(gL,'Align phase each step',{'Yes','No'},'No');
        wideButton(gL,'Read current XYZ position',@(~,~)freqSweepReadXYZ());

        q.method  = labeledDrop(gL,'Method',{'getDataAveraged','getData'},'getDataAveraged');
        q.channel = labeledNum (gL,'Scope channel',2);
        q.conv    = labeledDrop(gL,'conversion (getData)',{'true','false'},'true');
        q.adc     = labeledNum (gL,'adcMaxValue (2^16)',2^16);
        q.resetCh = labeledNum (gL,'Reset averaging channel',2);

        q.base = labeledText(gL,'Base folder',pwd);
        q.date = labeledText(gL,'Date folder',datestr(now,'yyyy-mm-dd'));
        q.file = labeledText(gL,'File name (.mat)','freq_sweep_1.mat');
        srow = uigridlayout(gL,[1 2]); srow.Layout.Column=[1 2]; srow.Padding=[0 0 0 0];
        srow.ColumnWidth = {'1x','1x'};
        uibutton(srow,'Text','Browse folder...','ButtonPushedFcn',@(~,~)browseInto('q'));
        uibutton(srow,'Text','Save .mat now','ButtonPushedFcn',@(~,~)freqSweepSave());

        q.prog = uilabel(gL,'Text','Idle.'); q.prog.Layout.Column=[1 2];
        brow = uigridlayout(gL,[1 2]); brow.Layout.Column=[1 2]; brow.Padding=[0 0 0 0];
        brow.ColumnWidth = {'1x','1x'};
        q.runBtn  = uibutton(brow,'Text','Run Freq Sweep','BackgroundColor',[0.2 0.6 0.2], ...
            'FontColor','w','ButtonPushedFcn',@(~,~)runFreqSweep());
        q.stopBtn = uibutton(brow,'Text','Stop','BackgroundColor',[0.7 0.2 0.2], ...
            'FontColor','w','ButtonPushedFcn',@(~,~)stopScanReq());
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[3 1]); pR.RowHeight = {66,'1x',28};
        crow = uigridlayout(pR,[1 4]); crow.Layout.Row=1;
        crow.ColumnWidth={'1x','1x','1x','1x'};
        q.cardX   = card(crow,'X pos','mm','%.3f');
        q.cardY   = card(crow,'Y pos','mm','%.3f');
        q.cardZ   = card(crow,'Z pos','mm','%.3f');
        q.cardPts = card(crow,'Points done','','%d');

        q.ax = uiaxes(pR); q.ax.Layout.Row=2;
        title(q.ax,'Peak amplitude vs frequency appears here');
        xlabel(q.ax,'Frequency (MHz)'); ylabel(q.ax,'Peak amplitude');
        rr = uigridlayout(pR,[1 4]); rr.Layout.Row=3; rr.ColumnWidth={'1x',120,120,120};
        q.sel = uidropdown(rr,'Items',{'(no sweep yet)'},'Enable','off', ...
            'ValueChangedFcn',@(~,~)plotFreqSweepSelected());
        uibutton(rr,'Text','Response','ButtonPushedFcn',@(~,~)plotFreqSweepResponse());
        uibutton(rr,'Text','Selected trace','ButtonPushedFcn',@(~,~)plotFreqSweepSelected());
        uibutton(rr,'Text','All traces','ButtonPushedFcn',@(~,~)plotFreqSweepAll());

        S.ui.q = q;
        refreshFreqSweepEnables();
        q.method.ValueChangedFcn = @(~,~)refreshFreqSweepEnables();
        freqSweepReadXYZ();          % show current position on tab creation
    end

    function refreshFreqSweepEnables()
        q = S.ui.q; isAvg = strcmp(q.method.Value,'getDataAveraged');
        q.resetCh.Enable = onoff(isAvg);
        q.conv.Enable    = onoff(~isAvg);
    end

    function pos = readXYZ()
        pos = [NaN NaN NaN]; axs = {'X','Y','Z'};
        for i = 1:3
            a = axs{i};
            if ~isempty(S.motor.(a))
                try, pos(i) = S.motor.(a).getPosition(); catch, end
            end
        end
    end

    function freqSweepReadXYZ()
        p = readXYZ();
        setCard(S.ui.q.cardX,p(1));
        setCard(S.ui.q.cardY,p(2));
        setCard(S.ui.q.cardZ,p(3));
    end

    function runFreqSweep()
        if ~requireGen();   return; end
        if ~requireScope(); return; end
        q = S.ui.q;

        genCh = round(q.genCh.Value);
        f1 = q.fStart.Value*1e6;
        f2 = q.fStop.Value*1e6;
        df = abs(q.fStep.Value)*1e6;
        if df <= 0; alertUser('Step must be > 0.','Freq sweep'); return; end
        if f2 >= f1; freqs = f1:df:f2; else; freqs = f1:-df:f2; end
        nF = numel(freqs);
        if nF < 1; alertUser('No frequencies in range.','Freq sweep'); return; end

        cfg.method  = q.method.Value;
        cfg.channel = q.channel.Value;
        cfg.conv    = strcmp(q.conv.Value,'true');
        cfg.adc     = q.adc.Value;

        if isempty(S.fsActual) || S.fsActual <= 0
            try, S.fsActual = S.osc.getSampleRate(); catch, S.fsActual = []; end
        end

        pos = readXYZ();                       % current XYZ, no motion
        freqSweepReadXYZ();

        if strcmp(q.outOn.Value,'Yes')
            safe(sprintf('output %d ON',genCh), @()S.gen.outputOn(genCh));
        end
        safe(sprintf('zero CH%d offset',cfg.channel), @()S.osc.setOffset(cfg.channel,0));

        allData = cell(1,nF); ampPk = nan(1,nF); t = [];
        S.stopScan = false; q.runBtn.Enable = 'off';
        cleaner = onCleanup(@()set(q.runBtn,'Enable','on')); %#ok<NASGU>
        setCard(q.cardPts,0);
        logMsg('Freq sweep: %d points, %.4f -> %.4f MHz on CH%d (fixed XYZ).', ...
            nF, f1/1e6, f2/1e6, genCh);

        done = 0;
        try
            for i = 1:nF
                if S.stopScan; break; end
                S.gen.setFrequency(genCh, freqs(i));
                if strcmp(q.align.Value,'Yes'); try, S.gen.alignPhase(); catch, end; end
                if strcmp(cfg.method,'getDataAveraged')
                    S.osc.resetAveragingByOffset(q.resetCh.Value);
                end
                interruptiblePause(q.settle.Value);
                if S.stopScan; break; end

                [data,t] = acquireTrace(cfg,t);
                allData{i} = data;
                d = data(:); ampPk(i) = max(abs(d - mean(d)));
                done = i;

                q.prog.Text = sprintf('Point %d of %d   f=%.4f MHz',i,nF,freqs(i)/1e6);
                setCard(q.cardPts,done);
                logMsg('Freq %d/%d: %.4f MHz (%d samples)',i,nF,freqs(i)/1e6,numel(data));
                drawnow limitrate;
                interruptiblePause(q.post.Value);
            end
        catch e
            logMsg('FREQ SWEEP ERROR: %s',e.message); alertUser(e.message,'Freq sweep error');
        end

        freqs = freqs(1:done); allData = allData(1:done); ampPk = ampPk(1:done);
        if done == 0; q.prog.Text = 'No data acquired.'; return; end

        S.fsweep = struct('freqs',freqs,'allData',{allData},'ampPk',ampPk, ...
            't',t,'pos',pos,'genCh',genCh);
        refreshFreqSweepSel();
        plotFreqSweepResponse();
        if ~isempty(strtrim(q.file.Value)); freqSweepSave(); end
        if S.stopScan; q.prog.Text = sprintf('Stopped after %d points (saved).',done);
        else;          q.prog.Text = sprintf('Done: %d points (saved).',done); end
    end

    function freqSweepSave()
        if isempty(S.fsweep); alertUser('Run a frequency sweep first.','Save'); return; end
        q = S.ui.q;
        folder = fullfile(q.base.Value, q.date.Value);
        if ~exist(folder,'dir')
            if ~safe('create folder', @()mkdir(folder)); return; end
        end
        fname = fullfile(folder, ensureMat(q.file.Value));
        allData = S.fsweep.allData; t = S.fsweep.t; freqs = S.fsweep.freqs;
        ampPk = S.fsweep.ampPk; pos = S.fsweep.pos; genCh = S.fsweep.genCh; %#ok<NASGU>
        try
            save(fname,'allData','t','freqs','ampPk','pos','genCh','-v7.3');
        catch e
            alertUser(sprintf('Could not save the file:\n%s',e.message),'Save .mat');
            logMsg('save .mat: %s', e.message); return;
        end
        logMsg('Saved frequency sweep (%d points) -> %s', numel(allData), fname);
    end

    function refreshFreqSweepSel()
        if isempty(S.fsweep); return; end
        Q = S.fsweep; n = numel(Q.allData);
        items = arrayfun(@(k)sprintf('point %d | f=%.4f MHz',k,Q.freqs(k)/1e6), ...
            1:n,'UniformOutput',false);
        S.ui.q.sel.Items = items; S.ui.q.sel.Enable='on'; S.ui.q.sel.Value=items{1};
    end

    function plotFreqSweepResponse()
        if isempty(S.fsweep); alertUser('Run a frequency sweep first.','Response'); return; end
        Q = S.fsweep; ax = S.ui.q.ax;
        cla(ax); ax.XLimMode='auto'; ax.YLimMode='auto';
        plot(ax, Q.freqs/1e6, Q.ampPk, '-o','LineWidth',1); grid(ax,'on');
        [pk,ip] = max(Q.ampPk);
        hold(ax,'on');
        plot(ax, Q.freqs(ip)/1e6, pk, 'rp','MarkerFaceColor','r','MarkerSize',12);
        xline(ax, Q.freqs(ip)/1e6,'r--');
        hold(ax,'off');
        title(ax,sprintf('Peak amplitude vs frequency  (max at %.4f MHz)',Q.freqs(ip)/1e6));
        xlabel(ax,'Frequency (MHz)'); ylabel(ax,'Peak amplitude (offset removed)');
    end

    function plotFreqSweepSelected()
        if isempty(S.fsweep); return; end
        q = S.ui.q; Q = S.fsweep;
        k = find(strcmp(q.sel.Items,q.sel.Value),1); if isempty(k); k=1; end
        d = zoff(Q.allData{k}); ax = q.ax;
        cla(ax); ax.XLimMode='auto'; ax.YLimMode='auto';
        plot(ax, Q.t*1e6, d, 'b');
        title(ax,sprintf('Trace at f=%.4f MHz (point %d)',Q.freqs(k)/1e6,k));
        xlabel(ax,'Time (us)'); ylabel(ax,'Amplitude (offset removed)');
    end

    function plotFreqSweepAll()
        if isempty(S.fsweep); return; end
        Q = S.fsweep; ax = S.ui.q.ax; cla(ax); hold(ax,'on');
        ax.XLimMode='auto'; ax.YLimMode='auto';
        for k = 1:numel(Q.allData)
            plot(ax, Q.t*1e6, zoff(Q.allData{k}),'Color',[0.55 0.55 0.55 0.5]);
        end
        hold(ax,'off');
        title(ax,sprintf('All %d traces - amplitude vs time',numel(Q.allData)));
        xlabel(ax,'Time (us)'); ylabel(ax,'Amplitude (offset removed)');
    end
%% ================================ ECHO ANALYSIS TAB ===================== %%
    function buildEchoTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {320,'1x'};

        pL = uipanel(g,'Title','Echo analysis (after scan)');
        gL = uigridlayout(pL,[13 2]);
        gL.RowHeight   = repmat({26},1,13);
        gL.ColumnWidth = {180,'1x'};
        gL.Scrollable  = 'on';

        a.sigStart= labeledNum(gL,'Signal win start (us)',0);
        a.sigEnd  = labeledNum(gL,'Signal win end (us)',50);
        a.noiseGap= labeledNum(gL,'Noise gap after peak (us)',4);
        a.noiseW  = labeledNum(gL,'Noise win width (us)',4);

        ab = uigridlayout(gL,[1 2]); ab.Layout.Column=[1 2]; ab.Padding=[0 0 0 0];
        ab.ColumnWidth={'1x','1x'};
        uibutton(ab,'Text','Analyze / Update SNR','BackgroundColor',[0.2 0.5 0.7], ...
            'FontColor','w','ButtonPushedFcn',@(~,~)analyzeEcho());
        uibutton(ab,'Text','Load .mat...','ButtonPushedFcn',@(~,~)loadEchoMat());

        a.sel = uidropdown(gL,'Items',{'(no data yet)'},'Enable','off', ...
            'ValueChangedFcn',@(~,~)plotEchoSelected());
        a.sel.Layout.Column=[1 2];
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[4 1]); pR.RowHeight = {84,'1x',38,28};
        cardrow = uigridlayout(pR,[1 2]); cardrow.Layout.Row=1; cardrow.ColumnWidth={'1x','1x'};
        a.cardSNR = card(cardrow,'Best SNR','dB','%.1f');
        a.cardZ   = card(cardrow,'Best Z position','mm','%.4f');

        a.ax = uiaxes(pR); a.ax.Layout.Row = 2;
        title(a.ax,'Set windows, then Analyze');
        xlabel(a.ax,'Time (us)'); ylabel(a.ax,'Amplitude');

        sr = uigridlayout(pR,[1 3]); sr.Layout.Row=3; sr.ColumnWidth={60,'1x',60};
        uilabel(sr,'Text','Trace:','HorizontalAlignment','right');
        a.slider = uislider(sr,'Limits',[1 2],'Value',1,'Enable','off', ...
            'MajorTicks',[],'ValueChangingFcn',@(s,e)sliderTrace(e.Value));
        a.sliderVal = uilabel(sr,'Text','-','HorizontalAlignment','center');

        rr = uigridlayout(pR,[1 4]); rr.Layout.Row=4;
        rr.ColumnWidth={'1x','1x','1x','1x'};
        uibutton(rr,'Text','Plot Selected','ButtonPushedFcn',@(~,~)plotEchoSelected());
        uibutton(rr,'Text','Plot All','ButtonPushedFcn',@(~,~)plotEchoAll());
        uibutton(rr,'Text','SNR vs Z','ButtonPushedFcn',@(~,~)plotEchoSNR());
        uibutton(rr,'Text','Amplitude vs Z','ButtonPushedFcn',@(~,~)plotEchoAmp());

        S.ui.a = a;
    end

    function analyzeEcho()
        if isempty(S.zscan) || ~isfield(S.zscan,'data_all')
            alertUser('Run or load a Z scan first.','Analysis'); return;
        end
        a = S.ui.a; Z = S.zscan;
        gates.sigStart = a.sigStart.Value*1e-6;
        gates.sigEnd   = a.sigEnd.Value*1e-6;
        gates.noiseGap = a.noiseGap.Value*1e-6;
        gates.noiseW   = a.noiseW.Value*1e-6;

        n = numel(Z.data_all);
        sigAmp=nan(1,n); noiseRMS=nan(1,n); snrdB=nan(1,n); peakIdx=nan(1,n);
        for k=1:n
            [sigAmp(k),noiseRMS(k),snrdB(k),peakIdx(k)] = analyseTrace(Z.data_all{k},Z.t,gates);
        end
        [bestSNR,bestK] = max(snrdB);
        S.zres = struct('gates',gates,'sigAmp',sigAmp,'noiseRMS',noiseRMS, ...
            'snrdB',snrdB,'peakIdx',peakIdx,'bestK',bestK);

        items = arrayfun(@(k)sprintf('step %d | Z=%.4f mm | SNR=%.1f dB', ...
            k,Z.positions_mm(k),snrdB(k)), 1:n,'UniformOutput',false);
        a.sel.Items=items; a.sel.Enable='on'; a.sel.Value=items{bestK};
        a.slider.Value = max(a.slider.Limits(1),min(a.slider.Limits(2),bestK));
        a.sliderVal.Text = sprintf('%d',bestK);
        setCard(a.cardSNR, bestSNR);
        setCard(a.cardZ,   Z.positions_mm(bestK));
        logMsg('Echo: best SNR %.1f dB at Z=%.4f mm (step %d).', ...
            bestSNR, Z.positions_mm(bestK), bestK);
        plotEchoSelected();
    end

    function [sigAmp,noiseRMS,snrdB,peakIdx] = analyseTrace(data,t,gates)
        data=zoff(data); t=t(:);          % remove DC offset (zero the trace)
        inSig = t>=gates.sigStart & t<=gates.sigEnd;
        if ~any(inSig); inSig = true(size(t)); end
        idxSig=find(inSig);
        [sigAmp,rel]=max(abs(data(inSig)));
        peakIdx=idxSig(rel);
        nStart=t(peakIdx)+gates.noiseGap;
        inN = t>=nStart & t<=(nStart+gates.noiseW);
        if ~any(inN); inN = t>=t(end)-0.1*(t(end)-t(1)); end
        noiseRMS=sqrt(mean(data(inN).^2));
        snrdB=20*log10(sigAmp/max(noiseRMS,eps));
    end

    function y = zoff(d)                   % subtract the mean -> zero offset
        d = d(:); y = d - mean(d);
    end

    function plotEchoSelected()
        if isempty(S.zscan); return; end
        a=S.ui.a; Z=S.zscan;
        k=find(strcmp(a.sel.Items,a.sel.Value),1); if isempty(k); k=1; end
        d=zoff(Z.data_all{k}); tt=Z.t(:)*1e6;
        cla(a.ax); hold(a.ax,'on'); plot(a.ax,tt,d,'b');
        if ~isempty(S.zres)                                   % analysed: show gates + SNR
            R=S.zres; pk=R.peakIdx(k);
            if ~isnan(pk); plot(a.ax,tt(pk),d(pk),'r^','MarkerFaceColor','r'); end
            g=R.gates; yl=ylim(a.ax);
            plotGate(a.ax,g.sigStart*1e6,g.sigEnd*1e6,yl,[0 0.6 0 0.12]);
            nS=tt(pk)+g.noiseGap*1e6; plotGate(a.ax,nS,nS+g.noiseW*1e6,yl,[0.7 0 0 0.12]);
            ttl=sprintf('Amplitude vs time  |  Z=%.4f mm  |  SNR=%.1f dB (step %d)', ...
                Z.positions_mm(k),R.snrdB(k),k);
        else
            ttl=sprintf('Amplitude vs time  |  Z=%.4f mm (step %d, raw)',Z.positions_mm(k),k);
        end
        hold(a.ax,'off');
        title(a.ax,ttl); xlabel(a.ax,'Time (us)'); ylabel(a.ax,'Amplitude (offset removed)');
    end

    function plotEchoAll()
        if isempty(S.zscan); return; end
        a=S.ui.a; Z=S.zscan; cla(a.ax); hold(a.ax,'on');
        for k=1:numel(Z.data_all)
            plot(a.ax,Z.t*1e6,zoff(Z.data_all{k}),'Color',[0.6 0.6 0.6 0.5]);
        end
        if ~isempty(S.zres)
            bk=S.zres.bestK;
            plot(a.ax,Z.t*1e6,zoff(Z.data_all{bk}),'r','LineWidth',1.2);
            ttl=sprintf('All %d traces - amplitude vs time (best SNR = red, Z=%.4f mm)', ...
                numel(Z.data_all),Z.positions_mm(bk));
        else
            ttl=sprintf('All %d traces - amplitude vs time (raw)',numel(Z.data_all));
        end
        hold(a.ax,'off');
        title(a.ax,ttl); xlabel(a.ax,'Time (us)'); ylabel(a.ax,'Amplitude (offset removed)');
    end

    function plotEchoAmp()
        if isempty(S.zres); alertUser('Analyze first.','Amplitude vs Z'); return; end
        a=S.ui.a; R=S.zres; Z=S.zscan; cla(a.ax); hold(a.ax,'on');
        plot(a.ax,Z.positions_mm,R.sigAmp,'-o');
        bz=Z.positions_mm(R.bestK); ba=R.sigAmp(R.bestK);
        xline(a.ax,bz,'r--');
        plot(a.ax,bz,ba,'rp','MarkerFaceColor','r','MarkerSize',12);
        text(a.ax,bz,ba,sprintf('  Z = %.4f mm',bz),'Color','r','FontWeight','bold');
        hold(a.ax,'off'); grid(a.ax,'on');
        title(a.ax,'Signal amplitude vs Z position');
        xlabel(a.ax,'Z (mm)'); ylabel(a.ax,'Peak amplitude (offset removed)');
    end

    function plotEchoSNR()
        if isempty(S.zres); return; end
        a=S.ui.a; R=S.zres; Z=S.zscan; cla(a.ax); hold(a.ax,'on');
        plot(a.ax,Z.positions_mm,R.snrdB,'-o');
        bz = Z.positions_mm(R.bestK); bs = R.snrdB(R.bestK);
        xline(a.ax,bz,'r--');
        plot(a.ax,bz,bs,'rp','MarkerFaceColor','r','MarkerSize',12);
        text(a.ax,bz,bs,sprintf('  Z = %.4f mm\n  SNR = %.1f dB',bz,bs), ...
            'Color','r','FontWeight','bold','VerticalAlignment','top');
        hold(a.ax,'off'); grid(a.ax,'on');
        title(a.ax,sprintf('SNR vs Z   (best: %.1f dB at Z=%.4f mm)',bs,bz));
        xlabel(a.ax,'Z (mm)'); ylabel(a.ax,'SNR (dB)');
    end

    function plotGate(ax,x1,x2,yl,rgba)
        patch(ax,[x1 x2 x2 x1],[yl(1) yl(1) yl(2) yl(2)],rgba(1:3), ...
            'FaceAlpha',rgba(4),'EdgeColor','none');
    end

    function loadEchoMat()
        [fn,fp] = uigetfile({'*.mat','MAT-files'},'Select a saved Z scan');
        if isequal(fn,0); return; end
        safe('load .mat', @()doLoadMat(fullfile(fp,fn)));
    end
    function doLoadMat(full)
        m = load(full);
        da  = pickField(m,{'data_all','allData'});
        tt  = pickField(m,{'t'});
        pos = pickField(m,{'positions_mm','positions','allZ'});
        if isempty(da) || isempty(tt); error('File must contain data_all and t.'); end
        if isempty(pos); pos = 1:numel(da); end
        S.zscan = struct('positions_mm',pos(:).','data_all',{da},'t',tt(:));
        S.zres = [];
        refreshZSel();
        logMsg('Loaded %d traces from %s', numel(da), full);
    end
    function v = pickField(m,names)
        v = [];
        for i=1:numel(names)
            if isfield(m,names{i}); v = m.(names{i}); return; end
        end
    end

%% ============================== MATERIAL ANALYSIS TAB ================== %%
    function buildMaterialTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {360,'1x'};

        pL = uipanel(g,'Title','Thickness & material (Carlson) from one trace');
        gL = uigridlayout(pL,[26 2]);
        gL.RowHeight   = repmat({24},1,26);
        gL.ColumnWidth = {185,'1x'};
        gL.Scrollable  = 'on';

        m.trace = labeledNum(gL,'Trace step',1);
        wideButton(gL,'Use best-SNR trace',@(~,~)matUseBest());
        wideButton(gL,'Load traces (.mat)...',@(~,~)matLoadTrace());

        wideLabel(gL,'--- Echo times (1 = excitation) ---');
        m.cfilm = labeledNum(gL,'Sound speed in film (m/s)',2700);
        m.e1 = labeledNum(gL,'Excitation time (us)',0.19);
        m.e2 = labeledNum(gL,'Echo 1 time (us)',1.54);
        m.e3 = labeledNum(gL,'Echo 2 time (us)',2.24);
        m.e4 = labeledNum(gL,'Echo 3 time (us)',2.99);
        m.gateHW = labeledNum(gL,'Gate half-width (us)',0.3);
        wideButton(gL,'Refine echo times (peaks)',@(~,~)matRefine());
        m.idx = labeledText(gL,'Indices (1=excitation)','2 3 4');

        wideLabel(gL,'--- Thickness ---');
        wideButton(gL,'Compute thickness (1st two indices)',@(~,~)matThickness());

        wideLabel(gL,'--- Carlson FFT inputs ---');
        m.cthick = labeledNum(gL,'Film thickness (um)',1000);
        wideButton(gL,'Copy computed thickness',@(~,~)matCopyThick());
        m.rhoW = labeledNum(gL,'Water density (kg/m^3)',1000);
        m.cW   = labeledNum(gL,'Water sound speed (m/s)',1480);
        m.fEval= labeledNum(gL,'Eval frequency (MHz)',10);
        m.fmin = labeledNum(gL,'Plot freq min (MHz)',1);
        m.fmax = labeledNum(gL,'Plot freq max (MHz)',20);
        wideButton(gL,'Run FFT analysis',@(~,~)matRunFFT());
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[3 1]); pR.RowHeight = {66,'1x',28};
        crow = uigridlayout(pR,[1 6]); crow.Layout.Row=1;
        crow.ColumnWidth={'1x','1x','1x','1x','1x','1x'};
        m.cardThick = card(crow,'Thickness','um','%.2f');
        m.cardDt    = card(crow,'Echo dt','ns','%.1f');
        m.cardAlpha = card(crow,'Attenuation','Np/m','%.1f');
        m.cardVel   = card(crow,'Velocity','m/s','%.0f');
        m.cardRho   = card(crow,'Density','kg/m^3','%.0f');
        m.cardKappa = card(crow,'Compressibility','1/Pa','%.3e');

        m.ax = uiaxes(pR); m.ax.Layout.Row = 2;
        title(m.ax,'Set echoes, then Compute / Run');
        xlabel(m.ax,'Time (us)'); ylabel(m.ax,'Amplitude');
        rr = uigridlayout(pR,[1 6]); rr.Layout.Row=3;
        rr.ColumnWidth = {'1x','1x','1x','1x','1x','1x'};
        uibutton(rr,'Text','Gated echoes','ButtonPushedFcn',@(~,~)plotMat('gated'));
        uibutton(rr,'Text','Spectra','ButtonPushedFcn',@(~,~)plotMat('spectra'));
        uibutton(rr,'Text','Attenuation','ButtonPushedFcn',@(~,~)plotMat('atten'));
        uibutton(rr,'Text','Velocity','ButtonPushedFcn',@(~,~)plotMat('vel'));
        uibutton(rr,'Text','Density','ButtonPushedFcn',@(~,~)plotMat('rho'));
        uibutton(rr,'Text','Compressibility','ButtonPushedFcn',@(~,~)plotMat('kappa'));

        S.ui.m = m;
    end

    function b = wideButton(parent,txt,cb)
        b = uibutton(parent,'Text',txt,'ButtonPushedFcn',cb);
        b.Layout.Column = [1 2];
    end
    function l = wideLabel(parent,txt)
        l = uilabel(parent,'Text',txt,'FontWeight','bold');
        l.Layout.Column = [1 2];
    end

    function [sig,t,k] = matTrace()
        sig=[]; t=[]; k=[];
        if isempty(S.zscan) || ~isfield(S.zscan,'data_all')
            alertUser('Run or load a Z scan first.','Material'); return;
        end
        n = numel(S.zscan.data_all);
        k = max(1,min(n,round(S.ui.m.trace.Value)));
        sig = zoff(S.zscan.data_all{k});
        t   = S.zscan.t(:);
    end

    function matUseBest()
        if ~isempty(S.zres); S.ui.m.trace.Value = S.zres.bestK;
        else; S.ui.m.trace.Value = 1; end
        [sig,t,k] = matTrace(); if isempty(sig); return; end
        cla(S.ui.m.ax); S.ui.m.ax.XLimMode='auto'; S.ui.m.ax.YLimMode='auto';
        plot(S.ui.m.ax, t*1e6, sig,'b');
        title(S.ui.m.ax,sprintf('Trace step %d (selected)',k));
        xlabel(S.ui.m.ax,'Time (us)'); ylabel(S.ui.m.ax,'Amplitude');
    end

    function matLoadTrace()
        [fn,fp] = uigetfile({'*.mat','MAT-files';'*.*','All files'}, ...
            'Select a trace or multi-trace scan');
        if isequal(fn,0); return; end
        safe('load traces', @() doLoadTrace(fullfile(fp,fn)));
    end
    function doLoadTrace(full)
        s = load(full);
        % --- collect one or many traces into a cell of column vectors ------
        da = pickField(s,{'data_all','allData'});
        if iscell(da) && ~isempty(da)
            da = cellfun(@(x)double(x(:)), da, 'UniformOutput',false);
        else
            d = pickField(s,{'data','collected_signal','trace','echo','signal','y','A'});
            if isempty(d); error('No trace found (looked for data, data_all, collected_signal, ...).'); end
            d = double(d);
            if isvector(d)
                da = {d(:)};
            else                                    % matrix: split into traces
                [r,c] = size(d);
                if r >= c                            % columns are traces (rows = samples)
                    da = arrayfun(@(j)d(:,j), 1:c, 'UniformOutput',false);
                else                                 % rows are traces
                    da = arrayfun(@(j)d(j,:).', 1:r, 'UniformOutput',false);
                end
            end
        end
        n = numel(da);
        nS = numel(da{1});
        % --- time vector ----------------------------------------------------
        tt = pickField(s,{'t','time'});
        if isempty(tt)
            if ~isempty(S.fsActual) && S.fsActual > 0
                tt = ((0:nS-1)*(1/(S.fsActual/2))).';
                logMsg('No t in file; built t from sample rate (dt = 1/(Fs/2)).');
            else
                error('File has no t and no sample rate is known. Read the sample rate first, or include t in the file.');
            end
        else
            tt = double(tt(:));
        end
        % --- positions ------------------------------------------------------
        pos = pickField(s,{'positions_mm','positions','allZ'});
        if isempty(pos); pos = 1:n; end
        pos = pos(:).';

        S.zscan = struct('positions_mm',pos,'data_all',{da},'t',tt);
        S.zres  = [];
        refreshZSel();
        if n > 1
            analyzeEcho();          % zero-offset + SNR on every trace, pick best
            logMsg('Loaded %d traces; offset zeroed and best SNR detected.', n);
        else
            S.ui.m.trace.Value = 1;
            logMsg('Loaded single trace (%d samples) from %s', nS, full);
        end
        matUseBest();               % select best (if analysed) and plot
    end

    function tp = refinePeak(sig,t,tc,hw)
        mask = abs(t-tc) <= hw;
        if ~any(mask); tp = tc; return; end
        idx = find(mask); [~,r] = max(abs(sig(idx))); tp = t(idx(r));
    end

    function matRefine()
        [sig,t] = matTrace(); if isempty(sig); return; end
        hw = S.ui.m.gateHW.Value*1e-6;
        flds = {S.ui.m.e1,S.ui.m.e2,S.ui.m.e3,S.ui.m.e4};
        for i = 1:numel(flds)
            if flds{i}.Value > 0
                flds{i}.Value = refinePeak(sig,t,flds{i}.Value*1e-6,hw)*1e6;
            end
        end
        logMsg('Echo times refined to local peaks.');
    end

    function te = matEchoTimes()
        te = [S.ui.m.e1.Value S.ui.m.e2.Value S.ui.m.e3.Value S.ui.m.e4.Value]*1e-6;
    end

    function matThickness()
        [sig,t] = matTrace(); if isempty(sig); return; end
        idx = str2num(S.ui.m.idx.Value); %#ok<ST2NM>
        if numel(idx) < 2; alertUser('Need at least two echo indices.','Thickness'); return; end
        hw = S.ui.m.gateHW.Value*1e-6; te = matEchoTimes();
        ta = refinePeak(sig,t,te(idx(1)),hw);
        tb = refinePeak(sig,t,te(idx(2)),hw);
        dt = abs(tb-ta);
        c  = S.ui.m.cfilm.Value;
        thick = c*dt/2;                        % metres (round-trip)
        S.mat_thick_um = thick*1e6;
        setCard(S.ui.m.cardThick, thick*1e6);
        setCard(S.ui.m.cardDt,    dt*1e9);
        logMsg('Thickness %.2f um from echoes %d,%d (dt=%.1f ns).', ...
            thick*1e6, idx(1), idx(2), dt*1e9);
        % show the two windows on the trace
        cla(S.ui.m.ax); hold(S.ui.m.ax,'on');
        S.ui.m.ax.XLimMode='auto'; S.ui.m.ax.YLimMode='auto';
        plot(S.ui.m.ax,t*1e6,sig,'b');
        yl = ylim(S.ui.m.ax);
        plotGate(S.ui.m.ax,(ta-hw)*1e6,(ta+hw)*1e6,yl,[0 0.6 0 0.12]);
        plotGate(S.ui.m.ax,(tb-hw)*1e6,(tb+hw)*1e6,yl,[0.7 0 0 0.12]);
        plot(S.ui.m.ax,[ta tb]*1e6,interp1(t,sig,[ta tb]),'r^','MarkerFaceColor','r');
        hold(S.ui.m.ax,'off');
        title(S.ui.m.ax,sprintf('Thickness windows  (%.2f um)',thick*1e6));
        xlabel(S.ui.m.ax,'Time (us)'); ylabel(S.ui.m.ax,'Amplitude');
    end

    function matCopyThick()
        if isfield(S,'mat_thick_um') && ~isempty(S.mat_thick_um)
            S.ui.m.cthick.Value = S.mat_thick_um;
            logMsg('Copied thickness %.2f um into Carlson input.',S.mat_thick_um);
        else
            alertUser('Compute thickness first.','Carlson');
        end
    end

    function matRunFFT()
        [sig,t] = matTrace(); if isempty(sig); return; end
        idx = str2num(S.ui.m.idx.Value); %#ok<ST2NM>
        if numel(idx) ~= 3
            alertUser('Carlson needs exactly 3 echo indices (e.g. 2 3 4).','Material'); return;
        end
        te = matEchoTimes(); hw = S.ui.m.gateHW.Value*1e-6;
        dt = t(2)-t(1); fs = 1/dt; N = numel(sig); NFFT = 2^nextpow2(N);
        f = (0:(NFFT/2)) * (fs/NFFT);
        Amplitude = zeros(3,numel(f)); FFT_complex = zeros(3,numel(f));
        gated = cell(1,3);
        try
            for ii = 1:3
                k = idx(ii);
                mask = abs(t - te(k)) <= hw;
                nn = nnz(mask);
                if nn < 2; error('Gate around echo %d is empty - check times/half-width.',k); end
                w = hann(nn);
                sg = zeros(size(sig)); sg(mask) = sig(mask).*w;
                gated{ii} = sg;
                F = fft(sg,NFFT); P1 = F(1:NFFT/2+1);
                FFT_complex(ii,:) = P1(:).';
                Amplitude(ii,:)   = abs(P1(:).') * (2/N);
            end
        catch e
            alertUser(e.message,'FFT analysis'); logMsg('FFT ERROR: %s',e.message); return;
        end

        thick = S.ui.m.cthick.Value/1e6;        % um -> m
        rhoW  = S.ui.m.rhoW.Value; cW = S.ui.m.cW.Value;
        A1 = -Amplitude(1,:); A2 = Amplitude(2,:); A3 = Amplitude(3,:);
        ratio_alpha = (A1.*A3 - A2.^2) ./ (A1.*A2);
        alpha_Np_m  = -(1/(2*thick)) * log(ratio_alpha);
        phi  = unwrap(angle(FFT_complex(2,:) ./ FFT_complex(1,:)));
        domega = 2*pi*(f(2)-f(1));
        Phi_w = gradient(phi, domega);
        c2 = abs((2*thick) ./ Phi_w);
        R12 = sqrt((A1.*A3) ./ (A1.*A3 - A2.^2));
        z1 = rhoW*cW; z2 = z1.*(1+R12)./(1-R12);
        rho2 = z2 ./ c2;
        kappa = 1 ./ (rho2 .* c2.^2);            % compressibility (1/Pa)

        S.mat = struct('f',f,'Amplitude',Amplitude,'FFT_complex',{FFT_complex}, ...
            'alpha',alpha_Np_m,'c2',c2,'rho2',rho2,'kappa',kappa,'gated',{gated}, ...
            't',t,'idx',idx,'thick',thick);

        % report at the evaluation frequency
        [~,jf] = min(abs(f - S.ui.m.fEval.Value*1e6));
        setCard(S.ui.m.cardAlpha, real(alpha_Np_m(jf)));
        setCard(S.ui.m.cardVel,   real(c2(jf)));
        setCard(S.ui.m.cardRho,   real(rho2(jf)));
        setCard(S.ui.m.cardKappa, real(kappa(jf)));
        logMsg(['Carlson @%.1f MHz: alpha=%.1f Np/m, c=%.0f m/s, ' ...
            'rho=%.0f kg/m^3, kappa=%.3e 1/Pa.'], f(jf)/1e6, real(alpha_Np_m(jf)), ...
            real(c2(jf)), real(rho2(jf)), real(kappa(jf)));
        plotMat('spectra');
    end

    function plotMat(kind)
        if isempty(S.mat); alertUser('Run FFT analysis first.','Material'); return; end
        M = S.mat; ax = S.ui.m.ax; fMHz = M.f/1e6;
        flim = sort([S.ui.m.fmin.Value S.ui.m.fmax.Value]);   % editable freq window
        cla(ax); ax.XLimMode='auto'; ax.YLimMode='auto'; hold(ax,'on');
        switch kind
            case 'gated'
                for ii = 1:3
                    plot(ax, M.t*1e6, M.gated{ii}, 'DisplayName',sprintf('echo %d',M.idx(ii)));
                end
                title(ax,'Gated echoes (Hann windowed)');
                xlabel(ax,'Time (us)'); ylabel(ax,'Amplitude'); legend(ax,'show');
            case 'spectra'
                for ii = 1:3
                    plot(ax, fMHz, M.Amplitude(ii,:), 'DisplayName',sprintf('echo %d',M.idx(ii)));
                end
                title(ax,'Echo amplitude spectra'); xlim(ax,flim);
                xlabel(ax,'Frequency (MHz)'); ylabel(ax,'Amplitude'); legend(ax,'show');
            case 'atten'
                plot(ax, fMHz, real(M.alpha)); title(ax,'Attenuation vs frequency');
                xlim(ax,flim); xlabel(ax,'Frequency (MHz)'); ylabel(ax,'\alpha (Np/m)');
            case 'vel'
                plot(ax, fMHz, real(M.c2)); title(ax,'Sound velocity vs frequency');
                xlim(ax,flim); xlabel(ax,'Frequency (MHz)'); ylabel(ax,'c (m/s)');
            case 'rho'
                plot(ax, fMHz, real(M.rho2)); title(ax,'Density vs frequency');
                xlim(ax,flim); xlabel(ax,'Frequency (MHz)'); ylabel(ax,'\rho (kg/m^3)');
            case 'kappa'
                plot(ax, fMHz, real(M.kappa)); title(ax,'Compressibility vs frequency');
                xlim(ax,flim); xlabel(ax,'Frequency (MHz)'); ylabel(ax,'\kappa (1/Pa)');
        end
        grid(ax,'on'); hold(ax,'off');
    end

%% =============================== XY ANALYSIS TAB ====================== %%
    function buildXYAnalysisTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {320,'1x'};

        pL = uipanel(g,'Title','XY scan analysis');
        gL = uigridlayout(pL,[11 2]);
        gL.RowHeight   = repmat({26},1,11);
        gL.ColumnWidth = {180,'1x'};
        gL.Scrollable  = 'on';

        wideButton(gL,'Load XY scan (.mat)...',@(~,~)loadXYMat());
        wideLabel(gL,'--- SNR windows ---');
        xa.sigStart= labeledNum(gL,'Signal win start (us)',0);
        xa.sigEnd  = labeledNum(gL,'Signal win end (us)',50);
        xa.noiseGap= labeledNum(gL,'Noise gap after peak (us)',4);
        xa.noiseW  = labeledNum(gL,'Noise win width (us)',4);
        wideButton(gL,'Analyze SNR',@(~,~)analyzeXY());
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[5 1]); pR.RowHeight = {66,'1x',24,38,30};
        crow = uigridlayout(pR,[1 3]); crow.Layout.Row=1;
        crow.ColumnWidth={'1x','1x','1x'};
        xa.cardSNR = card(crow,'Best SNR','dB','%.1f');
        xa.cardX   = card(crow,'Best X','mm','%.3f');
        xa.cardY   = card(crow,'Best Y','mm','%.3f');

        xa.ax = uiaxes(pR); xa.ax.Layout.Row=2;
        xlabel(xa.ax,'Time (us)'); ylabel(xa.ax,'Amplitude');

        xa.cap = uilabel(pR,'Text','Load or run an XY scan, then plot/analyze', ...
            'HorizontalAlignment','center','FontWeight','bold','FontColor',ACCENTD);
        xa.cap.Layout.Row = 3;

        srow = uigridlayout(pR,[1 3]); srow.Layout.Row=4; srow.ColumnWidth={60,'1x',60};
        uilabel(srow,'Text','Trace:','HorizontalAlignment','right');
        xa.slider = uislider(srow,'Limits',[1 2],'Value',1,'Enable','off', ...
            'MajorTicks',[],'ValueChangingFcn',@(s,e)sliderXYTrace(e.Value));
        xa.sliderVal = uilabel(srow,'Text','-','HorizontalAlignment','center');

        rr = uigridlayout(pR,[1 6]); rr.Layout.Row=5;
        rr.ColumnWidth={55,'1x','1x','1x','1x','1x'};
        uilabel(rr,'Text','Show:','HorizontalAlignment','right','FontWeight','bold');
        uibutton(rr,'Text','All traces','ButtonPushedFcn',@(~,~)plotXYAll());
        uibutton(rr,'Text','Single trace','ButtonPushedFcn',@(~,~)plotXYSingle());
        uibutton(rr,'Text','Amplitude map','ButtonPushedFcn',@(~,~)plotXYIntensity());
        uibutton(rr,'Text','SNR map','ButtonPushedFcn',@(~,~)plotXYSNRmap());
        uibutton(rr,'Text','Best trace','ButtonPushedFcn',@(~,~)plotXYBest());

        S.ui.xa = xa;
    end

    function xyCap(str)             % caption shown BELOW the XY plot
        S.ui.xa.cap.Text = str;
        title(S.ui.xa.ax,'');       % keep the top title empty
    end

    function loadXYMat()
        [fn,fp] = uigetfile({'*.mat','MAT-files';'*.*','All files'},'Select an XY scan');
        if isequal(fn,0); return; end
        safe('load XY scan', @() doLoadXY(fullfile(fp,fn)));
    end
    function doLoadXY(full)
        s = load(full);
        ad = pickField(s,{'allData','data_all'});
        if ~iscell(ad); error('No allData cell array found in the file.'); end
        [ny,nx] = size(ad);
        tt = pickField(s,{'t','time'});
        if isempty(tt)
            n1 = numel(ad{find(~cellfun(@isempty,ad),1)});
            if ~isempty(S.fsActual) && S.fsActual>0
                tt = ((0:n1-1)*(1/(S.fsActual/2))).';
                logMsg('No t in file; built t from sample rate (dt = 1/(Fs/2)).');
            else
                error('File has no t and no sample rate is known.');
            end
        end
        aX = pickField(s,{'allX'}); aY = pickField(s,{'allY'});
        if isempty(aX) || isempty(aY)
            [aX,aY] = meshgrid(1:nx,1:ny);            % index grid if positions missing
        end
        zp = pickField(s,{'zPos'}); if isempty(zp); zp = NaN; end
        S.xyscan = struct('allData',{ad},'allX',aX,'allY',aY,'t',tt(:), ...
            'xPositions',aX(1,:),'yPositions',aY(:,1).','zPos',zp);
        S.xyres = [];
        logMsg('Loaded XY scan %dx%d from %s', ny, nx, full);
        plotXYAll();
    end

    function tracesMat = xyTracesMatrix()
        cells = reshape(S.xyscan.allData,1,[]);
        keep = ~cellfun(@isempty,cells); cells = cells(keep);
        tracesMat = cell2mat(cellfun(@(c)c(:),cells,'UniformOutput',false));
        tracesMat = tracesMat - mean(tracesMat,1);     % remove offset (per trace)
    end

    function plotXYAll()
        if isempty(S.xyscan); alertUser('Run or load an XY scan first.','XY analysis'); return; end
        configXYSlider();
        ax = S.ui.xa.ax; tt = S.xyscan.t(:);
        M = xyTracesMatrix();
        cla(ax); colorbar(ax,'off'); ax.XLimMode='auto'; ax.YLimMode='auto';
        plot(ax, tt*1e6, M, 'LineWidth',1);
        yline(ax,0,'k--');
        axis(ax,'tight');
        xyCap(sprintf('All traces, offset removed (%d total)',size(M,2)));
        xlabel(ax,'Time (us)'); ylabel(ax,'Amplitude (a.u.)');
        grid(ax,'on');
    end

    function configXYSlider()
        if isempty(S.xyscan); return; end
        [ny,nx] = size(S.xyscan.allData); N = ny*nx;
        sl = S.ui.xa.slider;
        if N >= 2
            sl.Limits=[1 N]; sl.MajorTicks=unique(round(linspace(1,N,min(N,8)))); sl.Enable='on';
        else
            sl.Limits=[1 2]; sl.Enable='off';
        end
        if sl.Value < 1 || sl.Value > max(2,N); sl.Value = 1; end
    end

    function plotXYSingle()
        if isempty(S.xyscan); alertUser('Run or load an XY scan first.','XY analysis'); return; end
        configXYSlider();
        sliderXYTrace(S.ui.xa.slider.Value);
    end

    function sliderXYTrace(val)
        if isempty(S.xyscan); return; end
        X = S.xyscan; [ny,nx] = size(X.allData); N = ny*nx;
        k = max(1,min(N,round(val)));
        S.ui.xa.sliderVal.Text = sprintf('%d',k);
        [i,j] = ind2sub([ny nx],k);
        ax = S.ui.xa.ax; cla(ax); colorbar(ax,'off');
        ax.XLimMode='auto'; ax.YLimMode='auto';
        d = X.allData{i,j};
        if isempty(d)
            xyCap(sprintf('Trace [%d,%d] is empty',i,j)); return;
        end
        d = d(:)-mean(d(:)); tt = X.t(:)*1e6;
        hold(ax,'on'); plot(ax,tt,d,'b');
        if ~isempty(S.xyres)
            R=S.xyres; pk=R.pk(i,j);
            if ~isnan(pk); plot(ax,tt(pk),d(pk),'r^','MarkerFaceColor','r'); end
            g=R.gates; yl=ylim(ax);
            plotGate(ax,g.sigStart*1e6,g.sigEnd*1e6,yl,[0 0.6 0 0.12]);
            nS=tt(pk)+g.noiseGap*1e6; plotGate(ax,nS,nS+g.noiseW*1e6,yl,[0.7 0 0 0.12]);
            ttl=sprintf('Single trace [%d,%d]  X=%.3f Y=%.3f mm  SNR=%.1f dB', ...
                i,j,X.allX(i,j),X.allY(i,j),R.snr(i,j));
        else
            ttl=sprintf('Single trace [%d,%d]  X=%.3f Y=%.3f mm',i,j,X.allX(i,j),X.allY(i,j));
        end
        hold(ax,'off'); xyCap(ttl);
        xlabel(ax,'Time (us)'); ylabel(ax,'Amplitude (offset removed)');
    end

    function plotXYIntensity()
        if isempty(S.xyscan); alertUser('Run or load an XY scan first.','XY analysis'); return; end
        X = S.xyscan; [ny,nx] = size(X.allData);
        amp = nan(ny,nx);
        for i=1:ny, for j=1:nx
            d = X.allData{i,j};
            if ~isempty(d); d=d(:); amp(i,j)=max(abs(d-mean(d))); end
        end, end
        showMap(amp, 'Intensity map - peak amplitude (a.u.)');
    end

    function analyzeXY()
        if isempty(S.xyscan); alertUser('Run or load an XY scan first.','XY analysis'); return; end
        configXYSlider();
        xa = S.ui.xa; X = S.xyscan; t = X.t(:);
        gates.sigStart = xa.sigStart.Value*1e-6;
        gates.sigEnd   = xa.sigEnd.Value*1e-6;
        gates.noiseGap = xa.noiseGap.Value*1e-6;
        gates.noiseW   = xa.noiseW.Value*1e-6;
        [ny,nx] = size(X.allData);
        snr = nan(ny,nx); amp = nan(ny,nx); pk = nan(ny,nx);
        for i=1:ny, for j=1:nx
            d = X.allData{i,j};
            if ~isempty(d)
                [amp(i,j),~,snr(i,j),pk(i,j)] = analyseTrace(d,t,gates);
            end
        end, end
        [bestSNR,lin] = max(snr(:)); [bi,bj] = ind2sub([ny nx],lin);
        S.xyres = struct('snr',snr,'amp',amp,'pk',pk,'gates',gates, ...
            'bestI',bi,'bestJ',bj);
        setCard(xa.cardSNR, bestSNR);
        setCard(xa.cardX,   X.allX(bi,bj));
        setCard(xa.cardY,   X.allY(bi,bj));
        logMsg('XY best SNR %.1f dB at X=%.3f, Y=%.3f mm [%d,%d].', ...
            bestSNR, X.allX(bi,bj), X.allY(bi,bj), bi, bj);
        plotXYSNRmap();
    end

    function plotXYSNRmap()
        if isempty(S.xyres); alertUser('Press Analyze SNR first.','SNR map'); return; end
        showMap(S.xyres.snr, 'SNR map (dB)');
        hold(S.ui.xa.ax,'on');
        X = S.xyscan; R = S.xyres;
        plot(S.ui.xa.ax, X.allX(R.bestI,R.bestJ), X.allY(R.bestI,R.bestJ), ...
            'rp','MarkerFaceColor','r','MarkerSize',12);
        hold(S.ui.xa.ax,'off');
    end

    function showMap(map, ttl)
        ax = S.ui.xa.ax; X = S.xyscan;
        xv = X.allX(1,:); yv = X.allY(:,1).';
        cla(ax); ax.XLimMode='auto'; ax.YLimMode='auto';
        imagesc(ax, xv, yv, map); axis(ax,'xy'); axis(ax,'tight'); colorbar(ax);
        xyCap(ttl); xlabel(ax,'X (mm)'); ylabel(ax,'Y (mm)');
    end

    function plotXYBest()
        if isempty(S.xyres); alertUser('Press Analyze SNR first.','Best trace'); return; end
        ax = S.ui.xa.ax; X = S.xyscan; R = S.xyres;
        d = X.allData{R.bestI,R.bestJ}(:); d = d - mean(d); tt = X.t(:)*1e6;
        cla(ax); colorbar(ax,'off'); ax.XLimMode='auto'; ax.YLimMode='auto'; hold(ax,'on');
        plot(ax, tt, d, 'b');
        pk = R.pk(R.bestI,R.bestJ);
        if ~isnan(pk); plot(ax, tt(pk), d(pk), 'r^','MarkerFaceColor','r'); end
        g = R.gates; yl = ylim(ax);
        plotGate(ax, g.sigStart*1e6, g.sigEnd*1e6, yl, [0 0.6 0 0.12]);
        nS = tt(pk)+g.noiseGap*1e6; plotGate(ax, nS, nS+g.noiseW*1e6, yl, [0.7 0 0 0.12]);
        hold(ax,'off');
        xyCap(sprintf('Best-SNR trace  |  X=%.3f Y=%.3f mm  |  SNR=%.1f dB', ...
            X.allX(R.bestI,R.bestJ), X.allY(R.bestI,R.bestJ), R.snr(R.bestI,R.bestJ)));
        xlabel(ax,'Time (us)'); ylabel(ax,'Amplitude (offset removed)');
    end

%% ============================ SENSITIVITY / NEP TAB ==================== %%
    function buildSensTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {320,'1x'};

        pL = uipanel(g,'Title','Sensitivity & NEP (best-SNR trace)');
        gL = uigridlayout(pL,[11 2]);
        gL.RowHeight   = repmat({26},1,11);
        gL.ColumnWidth = {185,'1x'};
        gL.Scrollable  = 'on';

        wideButton(gL,'Load XY scan (.mat)...',@(~,~)loadXYMat());
        s.src = labeledDrop(gL,'Best trace from', ...
            {'XY Analysis best','Recompute here'},'XY Analysis best');
        wideLabel(gL,'--- Windows & pressure ---');
        s.pres = labeledNum(gL,'Applied pressure (kPa)',800);
        s.sigA = labeledNum(gL,'Signal win start (us)',5);
        s.sigB = labeledNum(gL,'Signal win stop (us)',13);
        s.noiA = labeledNum(gL,'Noise win start (us)',15);
        s.noiB = labeledNum(gL,'Noise win stop (us)',20);
        wideButton(gL,'Compute sensitivity & NEP',@(~,~)computeSensNEP());
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[4 1]); pR.RowHeight = {66,'1x',24,28};
        crow = uigridlayout(pR,[1 3]); crow.Layout.Row=1; crow.ColumnWidth={'1x','1x','1x'};
        s.cardSNR  = card(crow,'Best SNR','','%.1f');
        s.cardSens = card(crow,'Sensitivity','V/Pa','%.3e');
        s.cardNEP  = card(crow,'NEP','kPa','%.4f');

        s.ax = uiaxes(pR); s.ax.Layout.Row=2;
        xlabel(s.ax,'Time (us)'); ylabel(s.ax,'Amplitude (V)');
        s.cap = uilabel(pR,'Text','Load/scan data, set windows, then Compute', ...
            'HorizontalAlignment','center','FontWeight','bold','FontColor',ACCENTD);
        s.cap.Layout.Row = 3;
        rr = uigridlayout(pR,[1 2]); rr.Layout.Row=4; rr.ColumnWidth={'1x','1x'};
        uibutton(rr,'Text','Replot best trace','ButtonPushedFcn',@(~,~)plotSensBest());
        uilabel(rr,'Text','');

        S.ui.s = s;
    end

    function computeSensNEP()
        if isempty(S.xyscan) || ~isfield(S.xyscan,'allData')
            alertUser('Run or load an XY scan first.','Sensitivity'); return;
        end
        s = S.ui.s; X = S.xyscan; t = X.t(:).';      % row, like the freq trace
        ad = X.allData; n = numel(ad); [ny,nx] = size(ad);
        Pa = s.pres.Value*1e3;

        sigMask   = (t >= s.sigA.Value*1e-6) & (t <= s.sigB.Value*1e-6);
        noiseMask = (t >= s.noiA.Value*1e-6) & (t <= s.noiB.Value*1e-6);
        if ~any(sigMask) || ~any(noiseMask)
            alertUser('A window is empty - check start/stop times vs the trace length.','Sensitivity');
            return;
        end

        SNR = nan(n,1); sm = nan(n,1); nz = nan(n,1);
        useXY = strcmp(s.src.Value,'XY Analysis best');
        if useXY
            % use the best-SNR cell already found on the XY Analysis tab
            if isempty(S.xyres)
                alertUser('Press "Analyze SNR" on the XY Analysis tab first (or pick "Recompute here").', ...
                    'Sensitivity'); return;
            end
            bi = sub2ind([ny nx], S.xyres.bestI, S.xyres.bestJ);
        else
            % recompute the best cell using the windows below
            for k = 1:n
                d = ad{k}; if isempty(d); continue; end
                d = d(:).' - mean(d(:));
                sm(k) = max(abs(d(sigMask)));
                nz(k) = sqrt(mean(d(noiseMask).^2));
                SNR(k) = sm(k)/nz(k);
            end
            [~,bi] = max(SNR);
        end

        % metrics on the chosen best cell, using the windows below
        db = ad{bi}(:).' - mean(ad{bi}(:));          % offset correction
        sigMax_V   = max(abs(db(sigMask)));          % peak in signal window
        noiseRMS_V = sqrt(mean(db(noiseMask).^2));   % RMS noise (V)
        bestSNR    = sigMax_V / noiseRMS_V;
        sens = sigMax_V / Pa;                        % V/Pa
        NEP_Pa  = noiseRMS_V / sens;                 % Pa
        NEP_kPa = NEP_Pa / 1e3;

        S.sens = struct('bestIdx',bi,'sigMax_V',sigMax_V,'noiseRMS_V',noiseRMS_V, ...
            'sens',sens,'NEP_Pa',NEP_Pa,'NEP_kPa',NEP_kPa, ...
            'sigA',s.sigA.Value,'sigB',s.sigB.Value,'noiA',s.noiA.Value,'noiB',s.noiB.Value);

        setCard(s.cardSNR,  bestSNR);
        setCard(s.cardSens, sens);
        setCard(s.cardNEP,  NEP_kPa);
        [bI,bJ] = ind2sub([ny nx],bi);
        logMsg(['Sensitivity from %s cell [%d,%d]: %.2f kPa -> ' ...
            'S=%.3e V/Pa, NEP=%.5f kPa (SNR %.1f).'], ...
            ternary(useXY,'XY-analysis','recomputed'), bI,bJ, s.pres.Value, ...
            sens, NEP_kPa, bestSNR);
        plotSensBest();
    end

    function out = ternary(c,a,b), if c, out=a; else, out=b; end, end

    function plotSensBest()
        if isempty(S.sens); alertUser('Press Compute first.','Sensitivity'); return; end
        R = S.sens; X = S.xyscan; ad = X.allData;
        t = X.t(:).'; bi = R.bestIdx;
        d = ad{bi}(:).' - mean(ad{bi}(:));           % offset correction
        ax = S.ui.s.ax; cla(ax); colorbar(ax,'off');
        ax.XLimMode='auto'; ax.YLimMode='auto'; hold(ax,'on');
        plot(ax, t*1e6, d, 'Color',[0.20 0.40 0.75], 'LineWidth',1.2);
        yl = ylim(ax);
        plotGate(ax, R.sigA, R.sigB, yl, [0.30 0.70 0.30 0.30]);   % signal = green
        plotGate(ax, R.noiA, R.noiB, yl, [0.85 0.30 0.30 0.30]);   % noise  = red
        hold(ax,'off'); grid(ax,'on');
        [ny,nx] = size(ad); [biI,bjJ] = ind2sub([ny nx],bi);
        S.ui.s.cap.Text = sprintf(['Best-SNR trace [%d,%d]  X=%.3f Y=%.3f mm  |  ' ...
            'Sensitivity %.3e V/Pa  |  NEP %.4f kPa'], biI,bjJ, ...
            X.allX(biI,bjJ), X.allY(biI,bjJ), R.sens, R.NEP_kPa);
        title(ax,''); xlabel(ax,'Time (us)'); ylabel(ax,'Amplitude (V)');
    end

%% ========================= FP FREQUENCY RESPONSE TAB ================== %%
    function buildFreqTab(tab)
        g = uigridlayout(tab,[1 2]);
        g.ColumnWidth = {320,'1x'};

        pL = uipanel(g,'Title','FP frequency response');
        gL = uigridlayout(pL,[11 2]);
        gL.RowHeight   = repmat({26},1,11);
        gL.ColumnWidth = {185,'1x'};
        gL.Scrollable  = 'on';

        wideButton(gL,'Load FP sweep (.mat)...',@(~,~)fpLoadMat());
        f.idx    = labeledNum(gL,'Trace index',1);
        f.ignore = labeledNum(gL,'Ignore before (us)',0);
        f.win    = labeledNum(gL,'Window half-width (us)',0.2);
        f.fmin   = labeledNum(gL,'Freq plot min (MHz)',2);
        f.fmax   = labeledNum(gL,'Freq plot max (MHz)',20);
        wideButton(gL,'Compute FFT',@(~,~)fpCompute());
        wideButton(gL,'Save settings',@(~,~)quickSaveSettings());

        pR = uigridlayout(g,[4 1]); pR.RowHeight = {66,'1x','1x',34};
        crow = uigridlayout(pR,[1 3]); crow.Layout.Row=1; crow.ColumnWidth={'1x','1x','1x'};
        f.cardT  = card(crow,'Peak time','us','%.2f');
        f.cardF  = card(crow,'Center freq','MHz','%.2f');
        f.cardBW = card(crow,'-6 dB bandwidth','MHz','%.2f');

        f.tax = uiaxes(pR); f.tax.Layout.Row=2;
        title(f.tax,'FP signal (windowed, normalized)');
        xlabel(f.tax,'Time (us)'); ylabel(f.tax,'Norm. amplitude');
        f.fax = uiaxes(pR); f.fax.Layout.Row=3;
        title(f.fax,'FP amplitude spectrum (normalized)');
        xlabel(f.fax,'Frequency (MHz)'); ylabel(f.fax,'Norm. |amplitude|');

        srow = uigridlayout(pR,[1 3]); srow.Layout.Row=4; srow.ColumnWidth={60,'1x',60};
        uilabel(srow,'Text','Trace:','HorizontalAlignment','right');
        f.slider = uislider(srow,'Limits',[1 2],'Value',1,'Enable','off', ...
            'MajorTicks',[],'ValueChangingFcn',@(s,e)fpSlider(e.Value));
        f.sliderVal = uilabel(srow,'Text','-','HorizontalAlignment','center');

        S.ui.f = f;
    end

    function fpLoadMat()
        [fn,fp] = uigetfile({'*.mat','MAT-files';'*.*','All files'},'Select an FP sweep');
        if isequal(fn,0); return; end
        safe('load FP sweep', @() doLoadFP(fullfile(fp,fn)));
    end
    function doLoadFP(full)
        s = load(full);
        ad = pickField(s,{'allData','data_all'});
        if ~iscell(ad); error('No allData cell array found in the file.'); end
        tt = pickField(s,{'t','time'});
        if isempty(tt)
            n1 = numel(ad{find(~cellfun(@isempty,ad),1)});
            if ~isempty(S.fsActual) && S.fsActual>0
                tt = ((0:n1-1)*(1/(S.fsActual/2))).';
                logMsg('No t in file; built t from sample rate (dt = 1/(Fs/2)).');
            else
                error('File has no t and no sample rate is known.');
            end
        end
        S.fpscan = struct('allData',{ad},'t',tt(:)); S.fp = [];
        configFPSlider();
        logMsg('Loaded FP sweep (%d traces) from %s', numel(ad), full);
        fpCompute();
    end

    function configFPSlider()
        if isempty(S.fpscan); return; end
        N = numel(S.fpscan.allData); sl = S.ui.f.slider;
        if N >= 2
            sl.Limits=[1 N]; sl.MajorTicks=unique(round(linspace(1,N,min(N,8)))); sl.Enable='on';
        else
            sl.Limits=[1 2]; sl.Enable='off';
        end
        if sl.Value<1 || sl.Value>max(2,N); sl.Value=1; end
    end
    function fpSlider(val)
        if isempty(S.fpscan); return; end
        N = numel(S.fpscan.allData); k = max(1,min(N,round(val)));
        S.ui.f.sliderVal.Text = sprintf('%d',k);
        S.ui.f.idx.Value = k;
        fpCompute();
    end

    function fpCompute()
        if isempty(S.fpscan); alertUser('Load an FP sweep first.','FP'); return; end
        f = S.ui.f; X = S.fpscan; ad = X.allData; n = numel(ad);
        k = max(1,min(n,round(f.idx.Value)));
        sig = ad{k};
        if isempty(sig); alertUser(sprintf('Trace %d is empty.',k),'FP'); return; end
        sig = sig(:); tcol = X.t(:);
        N = numel(tcol); dt = tcol(2)-tcol(1); Fs = 1/dt;

        % peak (optionally ignoring an early region)
        idxs = (1:N).';
        if f.ignore.Value > 0; idxs = find(tcol >= f.ignore.Value*1e-6); end
        [~,rel] = max(abs(sig(idxs))); mp = idxs(rel);
        tPeak = tcol(mp);

        % Hamming window around the peak
        win  = f.win.Value*1e-6;
        mask = abs(tcol - tPeak) <= win;
        w    = hammingWin(nnz(mask));
        sigW = zeros(size(sig)); sigW(mask) = sig(mask).*w;
        sigNorm = sigW / max(abs(sigW));

        % one-sided amplitude spectrum
        Y  = fft(sigW); P2 = abs(Y/N);
        P1 = P2(1:floor(N/2)+1); P1 = P1(:).';
        P1(2:end-1) = 2*P1(2:end-1);
        fvec = Fs*(0:floor(N/2))/N;
        P1n  = P1 / max(P1);

        % summary metrics
        [~,fi] = max(P1); fc = fvec(fi);
        above = P1n >= 0.5;                       % -6 dB in amplitude
        flo = fvec(find(above,1,'first')); fhi = fvec(find(above,1,'last'));
        bw = fhi - flo;

        S.fp = struct('k',k,'t',tcol,'sigNorm',sigNorm,'f',fvec,'P1n',P1n, ...
            'tPeak',tPeak,'fc',fc,'bw',bw);

        setCard(f.cardT,  tPeak*1e6);
        setCard(f.cardF,  fc/1e6);
        setCard(f.cardBW, bw/1e6);
        logMsg('FP trace %d: peak @ %.2f us, centre %.2f MHz, -6 dB BW %.2f MHz.', ...
            k, tPeak*1e6, fc/1e6, bw/1e6);

        % plots
        cla(f.tax); plot(f.tax, tcol*1e6, sigNorm,'b','LineWidth',1);
        axis(f.tax,'tight'); grid(f.tax,'on');
        title(f.tax,sprintf('FP signal, windowed & normalized (trace %d)',k));
        xlabel(f.tax,'Time (us)'); ylabel(f.tax,'Norm. amplitude');

        cla(f.fax); plot(f.fax, fvec/1e6, P1n,'b','LineWidth',1);
        xlim(f.fax, sort([f.fmin.Value f.fmax.Value])); grid(f.fax,'on');
        title(f.fax,'FP amplitude spectrum (normalized)');
        xlabel(f.fax,'Frequency (MHz)'); ylabel(f.fax,'Norm. |amplitude|');
    end

    function w = hammingWin(nn)        % Hamming window (no toolbox needed)
        if nn <= 1; w = ones(max(nn,1),1); return; end
        w = 0.54 - 0.46*cos(2*pi*(0:nn-1).'/(nn-1));
    end

%% =================================== HELPERS ============================ %%
    function h = card(parent,titleText,unit,fmt)
        if nargin<4; fmt='%.3g'; end
        ttl = titleText; if ~isempty(unit); ttl = sprintf('%s (%s)',titleText,unit); end
        p = uipanel(parent,'Title',ttl,'BackgroundColor',PANEL, ...
            'ForegroundColor',MUTED,'FontWeight','bold','FontName',FONT,'FontSize',11);
        gl = uigridlayout(p,[1 1]); gl.Padding=[6 1 6 1]; gl.BackgroundColor=PANEL;
        h.val  = uilabel(gl,'Text','--','FontName',FONT,'FontSize',15, ...
            'FontWeight','bold','FontColor',ACCENTD,'HorizontalAlignment','center', ...
            'VerticalAlignment','center');
        h.unit = unit; h.fmt = fmt; h.panel = p;
    end
    function setCard(h,val)
        if isempty(val) || (isnumeric(val)&&isnan(val)); h.val.Text='--';
        else; h.val.Text = sprintf(h.fmt, val); end
    end

    function applyTheme()
        set(findall(fig,'Type','uipanel'),'ForegroundColor',ACCENTD, ...
            'FontWeight','bold','FontName',FONT);
        set(findall(fig,'Type','uilabel'),'FontName',FONT);
        try, set(findall(fig,'Type','uidropdown'),'FontName',FONT); catch, end
        bs = findall(fig,'Type','uibutton');
        for i = 1:numel(bs)
            b = bs(i); b.FontName = FONT; b.FontWeight = 'bold';
            t = b.Text;
            if contains(t,{'Run','Analyze','Apply','Connect','Compute','Read Sample'},'IgnoreCase',true)
                b.BackgroundColor = ACCENT; b.FontColor = 'w';
            elseif contains(t,{'Stop','Disconnect'},'IgnoreCase',true)
                b.BackgroundColor = DANGER; b.FontColor = 'w';
            else
                b.BackgroundColor = NEUBG; b.FontColor = NEUTX;
            end
        end
        % re-assert card value styling (panels were recoloured above)
        cards = findall(fig,'Type','uilabel','FontSize',17);
        set(cards,'FontColor',ACCENTD);
    end

    function f = labeledNum(parent,label,val)
        uilabel(parent,'Text',label,'HorizontalAlignment','right','FontColor',NEUTX);
        f = uieditfield(parent,'numeric','Value',val,'ValueDisplayFormat','%g');
    end
    function f = labeledText(parent,label,val)
        uilabel(parent,'Text',label,'HorizontalAlignment','right','FontColor',NEUTX);
        f = uieditfield(parent,'text','Value',val);
    end
    function f = labeledDrop(parent,label,items,val)
        uilabel(parent,'Text',label,'HorizontalAlignment','right','FontColor',NEUTX);
        f = uidropdown(parent,'Items',items,'Value',val);
    end
    function s = onoff(tf), if tf, s='on'; else, s='off'; end, end

    function quickSaveSettings()
        cfg = walkSettings(S.ui,'ui',struct(),'save'); %#ok<NASGU>
        try
            save(S.settingsFile,'-struct','cfg');
            logMsg('Settings saved -> %s', S.settingsFile);
            flashSaved();
        catch e
            alertUser(sprintf('Could not save settings:\n%s',e.message),'Save settings');
            logMsg('save settings: %s', e.message);
        end
    end
    function flashSaved()
        % brief confirmation in the header without a modal dialog
        try
            S.ui.log.Value = [S.ui.log.Value; {sprintf('   [settings saved %s]',datestr(now,'HH:MM:SS'))}];
            scroll(S.ui.log,'bottom');
        catch
        end
    end
    function saveAllSettings()
        [fn,fp] = uiputfile('*.mat','Save GUI settings as',S.settingsFile);
        if isequal(fn,0); return; end
        S.settingsFile = fullfile(fp,fn);
        quickSaveSettings();
    end
    function loadAllSettings()
        start = S.settingsFile;
        if exist(start,'file'); def = start; else; def = '*.mat'; end
        [fn,fp] = uigetfile('*.mat','Load GUI settings',def);
        if isequal(fn,0); return; end
        try
            cfg = load(fullfile(fp,fn));
        catch e
            alertUser(sprintf('Could not read the file:\n%s',e.message),'Load settings'); return;
        end
        S.settingsFile = fullfile(fp,fn);
        walkSettings(S.ui,'ui',cfg,'load');
        logMsg('Settings loaded <- %s', S.settingsFile);
    end
    function out = walkSettings(node,key,out,mode)
        if isstruct(node) && isscalar(node)
            fn = fieldnames(node);
            for i = 1:numel(fn)
                out = walkSettings(node.(fn{i}), [key '_' fn{i}], out, mode);
            end
        elseif iscell(node)
            for i = 1:numel(node)
                out = walkSettings(node{i}, sprintf('%s_c%d',key,i), out, mode);
            end
        elseif isSettingCtrl(node)
            k = matlab.lang.makeValidName(key);
            if strcmp(mode,'save')
                out.(k) = node.Value;
            elseif isfield(out,k)
                try, node.Value = out.(k); catch, end
            end
        end
    end
    function tf = isSettingCtrl(h)
        tf = false;
        if ~(isscalar(h) && isobject(h)); return; end
        try, if ~isvalid(h); return; end; catch, return; end
        tf = isa(h,'matlab.ui.control.NumericEditField') || ...
             isa(h,'matlab.ui.control.EditField') || ...
             isa(h,'matlab.ui.control.DropDown');
    end

    function browseInto(id)
        h = S.ui.(id).base;             % look up live (after S.ui.(id) is assigned)
        start = h.Value; if isempty(start) || ~ischar(start); start = pwd; end
        d = uigetdir(start,'Select folder');
        if ischar(d) && ~isequal(d,0); h.Value = d; end
    end
    function f = ensureMat(name)
        if isempty(regexpi(name,'\.mat$','once')); f = [name '.mat']; else; f = name; end
    end

    function interruptiblePause(sec)
        tic0 = tic;
        while toc(tic0) < sec
            if S.stopScan; return; end
            pause(0.1); drawnow limitrate;
        end
    end

    function step(desc,fn)
        try, fn(); logMsg('  ok  %s',desc);
        catch e, logMsg('  ERR %s : %s',desc,e.message); end
    end
    function ok = safe(desc,fn)
        ok = false;
        try, fn(); logMsg('OK : %s',desc); ok = true;
        catch e, logMsg('ERROR (%s): %s',desc,e.message); alertUser(e.message,desc); end
    end
    function ok = callGen(fn), fn(); ok = true; end

    function tf = requireGen()
        tf = ~isempty(S.gen);
        if ~tf; alertUser('Connect the signal generator first.','Not connected'); end
    end
    function tf = requireScope()
        tf = ~isempty(S.osc);
        if ~tf; alertUser('Connect the oscilloscope first.','Not connected'); end
    end
    function tf = requireMotor(ax)
        tf = ~isempty(S.motor.(ax));
        if ~tf; alertUser(sprintf('Connect the %s motor first.',ax),'Not connected'); end
    end

    function revertSwitch(sw), sw.Value = sw.Items{1}; end
    function alertUser(msg,title), try, uialert(fig,msg,title); catch, end, end

    function logMsg(varargin)
        line = sprintf('[%s] %s',datestr(now,'HH:MM:SS'),sprintf(varargin{:}));
        cur = S.ui.log.Value;
        if isscalar(cur) && isempty(cur{1}); S.ui.log.Value = {line};
        else; S.ui.log.Value = [cur; {line}]; end
        try, scroll(S.ui.log,'bottom'); catch, end
        drawnow limitrate;
    end
end
