classdef T3DSO2502A < handle % This creates a handle class (meaning the object is passed by reference).
                             % Used to control the oscilloscope remotely.
    properties
        visaObj              % VISA object to communicate with the oscilloscope
        ipAddress            % IP address of the instrument
        verticalScale = zeros(1,4);
    end
   
    methods
        % Constructor
        function obj = T3DSO2502A(ipAddress)
            obj.ipAddress = ipAddress;
            obj.visaObj = visa('ni', ['TCPIP0::' ipAddress '::INSTR']);
            %'USB0::0xF4EC::0x1011::T0101C21340759::INSTR'); %['TCPIP0::' ipAddress '::INSTR']);
        end
       
        % Connect to the function generator
        function connect(obj)
            fopen(obj.visaObj);
        end
       
        % Disconnect from the function generator
        function disconnect(obj)
            fclose(obj.visaObj);
        end
       
        % Set frequency% Sets how much data can be received at once
        function setInputBufferSize(obj, inputBufferSize)
            %             fprintf(obj.visaObj, sprintf('Input Buffer Size %f', inputBufferSize));
            obj.visaObj.InputBufferSize = inputBufferSize;
        end
       
        % Set the timeout % Defines how long MATLAB waits before giving up on a response.
        function setTimeout(obj, T)
%       fprintf(obj.visaObj, sprintf('Input Buffer Size %f', T));
                   obj.visaObj.Timeout = T;
        end
       
        % Set time scale
        function setTimeScale(obj, timeScale)
            fprintf(obj.visaObj, sprintf('TIM:SCAL %f',  timeScale));
        end
       
        % Set time scale % shifts the time window
        function setTimebaseDelay(obj, timebaseDelay)
            fprintf(obj.visaObj, 'TIM:DEL %f', timebaseDelay);
        end      

        % Set acquisition type % NORMAL or AVERAGE
        function setAcquisitionType(obj, acquisitionType)
            fprintf(obj.visaObj, 'ACQ:TYPE %s', acquisitionType);
        end
       
        % Set vertical scale % Adjust y-axis scale and shift for a given channel.
        function setVerticalScale(obj, channel, verticalScale)
            fprintf(obj.visaObj, sprintf(':CHAN%d:SCAL %f', channel, verticalScale));
            obj.verticalScale(channel) = verticalScale;
        end
       
        % Set function vertical scale % Control internal math or function channels (e.g., FFT, average)
        function setFunctionVerticalScale(obj, channel, verticalScale)
            fprintf(obj.visaObj, sprintf('FUNC%d ON', channel));
            fprintf(obj.visaObj, sprintf(':FUNC%d:SCAL %f', channel, verticalScale));
        end
       
        % Close Function channel
        function closeFunction(obj, channel)
            fprintf(obj.visaObj, sprintf('FUNC%d OFF', channel));
        end
         % sampleRate is in Sa/s (Samples per second), e.g. 500e6 for 500 MSa/s
        function setSampleRate(obj, sampleRate)
            fprintf(obj.visaObj, sprintf('ACQ:SRAT %e', sampleRate));
        end
       
        function sampleRate = getSampleRate(obj)
            fprintf(obj.visaObj, 'ACQ:SRAT?');
            response = fscanf(obj.visaObj);
            sampleRate = str2double(response);
        end

       
        % Set offset % It doesn't change the signal itself ??? it just moves
        % the trace up or down so you can:
        % 1. Align multiple signals
        % 2. Center a waveform
        function setOffset(obj, channel, offset)
            fprintf(obj.visaObj, sprintf(':CHAN%d:OFFS %f', channel, offset));
        end
       
        % Set trigger source % This function controls how the oscilloscope triggers, which is essential for capturing stable waveforms
        function setTriggerSource(obj, channel)
            fprintf(obj.visaObj, sprintf(':TRIG:SOUR CHAN%d', channel));
        end
        % Set trigger type (edge, pulse, video, etc.)
        function setTriggerType(obj, type)
            fprintf(obj.visaObj, ':TRIG:TYPE %s', type);
        end
       
        % Set impedence % Set input impedance (typically '50' or '1M' ohm)
        function setImpedance(obj, channel, imp)
            fprintf(obj.visaObj, sprintf('CHAN%d:IMP %s', channel, imp));
        end
           
        % Set trigger level % Voltage level
        function setTriggerLevel(obj, triggerLevel)
            fprintf(obj.visaObj, sprintf(':TRIG:EDGE:LEV %f', triggerLevel));
        end
               
        % Set trigger mode % mode: AUTO, NORMAL, SINGLE
        function setTriggerMode(obj, mode)
            fprintf(obj.visaObj, sprintf(':TRIG:MODE %s', mode));
        end
%        
%         % query anything
%         function query(obj, string)
%             fprintf(obj.visaObj,string);
%               fread(vt
%         end
       
        % Averaging
        function data = getDataAverage(obj, channel, source, op, conversion,adcMaxValue)
           
            fprintf(obj.visaObj, sprintf('FUNC%d:SOUR1 C%d', channel, source));% set function channel: function channel (e.g., FUNC1) % source: data source (e.g., CH1)
            fprintf(obj.visaObj, sprintf('FUNC%d:OPER %s', channel, op));% set operation op: operation (e.g., AVER, FFT)
            fprintf(obj.visaObj, sprintf(':WAVeform:SOURce F%d', channel)); % Set Waveform Source to Function Channel, I want to download the waveform from function channel F1 (FUNC1).
            fprintf(obj.visaObj, ':WAV:DATA?');% Requests the binary waveform block
            data = binblockread(obj.visaObj, 'int16'); %Converts raw 16-bit ADC values to voltage using stored vertical scale.
            if conversion == 1
                data = (data/adcMaxValue)*(obj.verticalScale(source)*8);
            end                      
        end
       
        % acquisition
        function data = getData(obj, channel, conversion, adcMaxValue)
            fprintf(obj.visaObj, sprintf(':WAVeform:SOURce C%d', channel));% I want to read the waveform from channel C1 (if channel = 1).
            fprintf(obj.visaObj, ':WAV:DATA?');% Requests the binary waveform block
            data = binblockread(obj.visaObj, 'int16'); % Signed 16-bit integers (raw ADC units)
            if conversion == 1 % This converts raw ADC values to real voltages
                data = (data/adcMaxValue)*(obj.verticalScale(channel)*8);
            end
        end
       
           % acquisition from averaged channel using math function
         function data = getDataAveraged(obj, channel, conversion, adcMaxValue) % for now set the averaging count manually on oscilloscope
            % configure averaging on F1 channel
            fprintf(obj.visaObj,'FUNC1 ON');% turn on math on channel F1
            fprintf(obj.visaObj,'FUNC1:OPER AVER');% read the averaged waveform from channel F1
            fprintf(obj.visaObj,sprintf('FUNC1:SOUR1 C%d', channel));% configure source channel
        
            fprintf(obj.visaObj,':WAVeform:SOURce F1');% rblockead the averaged waveform from channel F1
            fprintf(obj.visaObj, ':WAV:DATA?');% Requests the binary waveform
            data = binblockread(obj.visaObj, 'int16'); % Signed 16-bit integers (raw ADC units)
            if conversion == 1 % This converts raw ADC values to real voltages
                data = (data/adcMaxValue)*(obj.verticalScale(channel)*8);
            end
          end
        

%         function data = getDataAveraged(obj, conversion, adcMaxValue) % averaging configured manually on oscilloscope
%             % Query the vertical scale of the MATH channel F1
%             fprintf(obj.visaObj, ':FUNC1:SCAL?');
%             funcScale = str2double(fscanf(obj.visaObj));
%         
%             fprintf(obj.visaObj,':WAVeform:SOURce F1');% read the averaged waveform from F1
%             fprintf(obj.visaObj, ':WAV:DATA?');% Requests the binary waveform
%             data = binblockread(obj.visaObj, 'int16'); % Signed 16-bit integers (raw ADC units)
%             if conversion == 1 % Convert raw ADC values to real voltages
%                 data = (data/adcMaxValue)*(funcScale*8);
%             end
%         end
        
        % delete obj % Ensures the VISA connection is closed and the object is destroyed properly when the class is deleted.
        function delete(obj)
            if strcmp(obj.visaObj.Status,'open')
                fclose(obj.visaObj);
            end
            delete(obj.visaObj);
        end
       
      function resetAveragingByOffset(obj, channel)
            % RESETAVERAGINGBYOFFSET - resets averaging by toggling channel offset slightly
           
            if strcmp(obj.visaObj.Status, 'closed')
                fopen(obj.visaObj);
            end

            % Query current offset
            fprintf(obj.visaObj, sprintf(':CHAN%d:OFFS?', channel));
            currentOffset = str2double(fscanf(obj.visaObj));

            % Apply offset change 
            newOffset = currentOffset + 1;
            fprintf(obj.visaObj, sprintf(':CHAN%d:OFFS %f', channel, newOffset));
            pause(0.5);

            % Restore original offset
            fprintf(obj.visaObj, sprintf(':CHAN%d:OFFS %f', channel, currentOffset));
            pause(1);
      end
        
       function resetAveragingByTrigger(obj)

            if strcmp(obj.visaObj.Status, 'closed')
        fopen(obj.visaObj);
            end

         % Stop acquisition
            fprintf(obj.visaObj, ':STOP');
            pause(0.2);

             % Restart acquisition
            fprintf(obj.visaObj, ':RUN');
            pause(0.5);

            end
        
       % Vertical setting of averaging trace
        function setFunctionVerticalScaleAve(obj, channel, verticalScale)
        fprintf(obj.visaObj, sprintf('FUNC%d ON', channel));
        fprintf(obj.visaObj, sprintf(':FUNC%d:SCAL %f', channel, verticalScale));
        end
        function setFunctionOffsetAve(obj, channel, offset)
        fprintf(obj.visaObj, sprintf(':FUNC%d:OFFS %f', channel, offset));
        end
    end
end