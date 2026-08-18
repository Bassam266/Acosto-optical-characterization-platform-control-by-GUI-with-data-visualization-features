classdef DG5000Pro < handle
    properties
        VisaObj
    end
    
    methods
        function obj = DG5000Pro(resourceName)
            obj.VisaObj = visadev(resourceName);
            %obj.VisaObj.Terminator = 'LF';
        end

        function connect(obj)
            % Connection is handled in constructor, but kept for compatibility
            fprintf('Connected to: %s\n', writeread(obj.VisaObj, '*IDN?'));
        end

        %% Waveform and Basic Parameters
        function setWaveform(obj, ch, type)
            % type: SINE, SQUARE, RAMP, PULSE, NOISE, DC, ARB
            writeline(obj.VisaObj, sprintf(':SOURce%d:FUNCtion %s', ch, type));
        end

        function setFrequency(obj, ch, freq)
            writeline(obj.VisaObj, sprintf(':SOURce%d:FREQuency %g', ch, freq));
        end

        function setAmplitude(obj, ch, amp)
            writeline(obj.VisaObj, sprintf(':SOURce%d:VOLTage %g', ch, amp));
        end

        function setOffset(obj, ch, offset)
            writeline(obj.VisaObj, sprintf(':SOURce%d:VOLTage:OFFSet %g', ch, offset));
        end

        function setPhase(obj, ch, phase)
            writeline(obj.VisaObj, sprintf(':SOURce%d:PHASE %g', ch, phase));
        end

        %% Pulse Specific Functions
        function setPulseWidth(obj, ch, width)
            writeline(obj.VisaObj, sprintf(':SOURce%d:FUNCtion:PULSe:WIDTh %g', ch, width));
        end

        function setRiseTime(obj, ch, rise)
            % DG5000 Pro uses Leading Edge for rise time
            writeline(obj.VisaObj, sprintf(':SOURce%d:FUNCtion:PULSe:TRANsition:LEADing %g', ch, rise));
        end

        function setDelay(obj, ch, delay)
            writeline(obj.VisaObj, sprintf(':TRIGger%d:DELay %g', ch, delay));
        end
        %% Square wave
        function setSquareDutyCycle(obj, ch, duty)
        writeline(obj.VisaObj, sprintf(':SOURce%d:FUNCtion:SQUare:DCYCle %g', ch, duty));
        end
        function setIdleLevel(obj, ch, position)
        % position: 'TOP', 'BOTTom', 'CENTer', or 'FPT'
        writeline(obj.VisaObj, sprintf(':OUTPut%d:IDLE %s', ch, position));
        end
        %% Burst Functions
        function setBurstState(obj, ch, state)
            % state: 'ON' or 'OFF'
            writeline(obj.VisaObj, sprintf(':SOURce%d:BURSt:STATe %s', ch, state));
        end

        function setBurstCycles(obj, ch, cycles)
            writeline(obj.VisaObj, sprintf(':SOURce%d:BURSt:NCYCles %d', ch, cycles));
        end

        function setBurstPeriod(obj, ch, period)
            writeline(obj.VisaObj, sprintf(':SOURce%d:BURSt:INTernal:PERiod %g', ch, period));
        end

        function setBurstSource(obj, ch, source)
            % source: 'IMMediate' (Internal), 'EXTernal', 'BUS' (Manual)
            if strcmpi(source, 'INT')
                source = 'IMMediate';
            end
            writeline(obj.VisaObj, sprintf(':TRIGger%d:SOURce %s', ch, source));
        end

        function trigger(obj, ch)
            % Manually trigger the channel (valid when Source is BUS)
            writeline(obj.VisaObj, sprintf(':TRIGger%d:IMMediate', ch));
        end

        function outputOn(obj, ch)
            writeline(obj.VisaObj, sprintf(':OUTPut%d:STATe ON', ch));
        end
        function outputOff(obj, ch)
            writeline(obj.VisaObj, sprintf(':OUTPut%d:STATe OFF', ch));
        end
        %% Synchronization and Alignment
        function alignPhase(obj)
            % Resets the phase of all channels to the same starting point
            writeline(obj.VisaObj, ':SOURce1:PHASe:SYNChronize');
        end
        function setBundle(obj, channels)
            % Channels: string like 'CH1,CH2'
            % Groups channels together for sync operations
            writeline(obj.VisaObj, sprintf(':SYNChro:BUNDle %s', channels));
        end

        function setBenchmark(obj, ch)
            % Sets the Master/Reference channel (e.g., 'CH1')
            writeline(obj.VisaObj, sprintf(':SYNChro:BENChmark %s', ch));
        end

        function setTrack(obj, ch, state)
            % state: 'ON' or 'OFF'. Mirror master channel settings
            % Note: This command is often grouped under PHASE or SOURCE depending on model firmware
            writeline(obj.VisaObj, sprintf(':SOURce%d:TRACk %s', ch, state));
        end
        
        function unlock(obj)
           
            writeline(obj.VisaObj, ':SYSTem:KLOCK OFF');
        end
% for get and set the wave generator impedance 

        function setImpedance(obj, ch, value)
        % value: numeric ohms (1 to 10000), e.g. 50
          %        or 'INF' / 'HIGHZ' for High-Z
    %        or 'MIN' / 'MAX' / 'DEF'
    if ischar(value) || isstring(value)
        v = upper(string(value));
        if any(v == ["INF","INFINITY","HIGHZ","HIZ"])
            arg = 'INFinity';
        else
            arg = char(v);            % MIN / MAX / DEF
        end
    else
        arg = sprintf('%g', value);   % numeric ohms, e.g. 50
    end
    writeline(obj.VisaObj, sprintf(':OUTPut%d:LOAD %s', ch, arg));
end

function imp = getImpedance(obj, ch)
    % Returns ohms as a number
    raw = writeread(obj.VisaObj, sprintf(':OUTPut%d:LOAD?', ch));
    val = str2double(raw);
    if val >= 9.9e37
        imp = Inf;                    % HighZ
    else
        imp = val;                    % e.g. 50, 100
    end
end
    
    end
end