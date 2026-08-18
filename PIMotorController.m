classdef PIMotorController < handle
    % Class to control PI stages via MATLAB GCS2 driver
properties
        Controller          % PI_GCS_Controller object
        Device              % PI device object
        SerialNumber        % Controller serial number
        Axis = '1';         % Default axis
end
methods
        %% Constructor
function obj = PIMotorController(serialNumber, axis)
if nargin > 0
                obj.SerialNumber = serialNumber;
end
if nargin > 1
                obj.Axis = axis;
end
% Add PI driver path
if ispc
                addpath(getenv('PI_MATLAB_DRIVER'));
else
                addpath('/usr/local/PI/pi_matlab_driver_gcs2');
end
            obj.Controller = PI_GCS_Controller();
end
        %% Connect to device
function connect(obj)
            devices = obj.Controller.EnumerateUSB('');
            disp('Connected devices:');
            disp(devices);
            obj.Device = obj.Controller.ConnectUSB(obj.SerialNumber);
            disp(['Connected to: ', obj.Device.qIDN()]);
            obj.Device = obj.Device.InitializeController();
end
        %% Enable/disable servo
function setServo(obj, state)
            obj.Device.SVO(obj.Axis, state);
            pause(0.2);
if obj.Device.qSVO(obj.Axis) ~= state
                error('Failed to change servo state');
end
end
        %% Reference (home) the stage
function reference(obj, method)
% method: 'FRF' reference switch (default), 'FNL' neg limit, 'FPL' pos limit
if nargin < 2 || isempty(method)
                method = 'FRF';
end
            method = upper(method);
% allow referencing
            obj.Device.RON(obj.Axis, true);
% start the reference move
switch method
case 'FRF'
                    obj.Device.FRF(obj.Axis);
case 'FNL'
                    obj.Device.FNL(obj.Axis);
case 'FPL'
                    obj.Device.FPL(obj.Axis);
otherwise
                    error('Unknown reference method: %s (use FRF, FNL or FPL)', method);
end
% wait for the reference move to finish
while obj.Device.IsMoving(obj.Axis)
                pause(0.1);
end
% confirm it actually referenced
if ~obj.Device.qFRF(obj.Axis)
                error('Referencing failed on axis %s', obj.Axis);
end
            fprintf('Axis %s referenced (%s). Position = %.4f\n', ...
                obj.Axis, method, obj.Device.qPOS(obj.Axis));
end
        %% Check if referenced
function tf = isReferenced(obj)
            tf = logical(obj.Device.qFRF(obj.Axis));
end
        %% Get travel range
function [minPos, maxPos, range] = getTravelRange(obj)
            minPos = obj.Device.qTMN(obj.Axis);
            maxPos = obj.Device.qTMX(obj.Axis);
            range = maxPos - minPos;
end
        %% Absolute move
function moveAbs(obj, target)
            obj.Device.MOV(obj.Axis, target);
while ~obj.Device.qONT(obj.Axis)
                pause(0.1);
end
end
        %% Relative move
function moveRel(obj, step)
            obj.Device.MVR(obj.Axis, step);
while ~obj.Device.qONT(obj.Axis)
                pause(0.1);
end
end
        %% Get current position
function pos = getPosition(obj)
            pos = obj.Device.qPOS(obj.Axis);
end
        %% Disconnect
function disconnect(obj)
            obj.setServo(false);
            obj.Device.CloseConnection();
            obj.Controller.Destroy();
            clear obj.Controller;
            clear obj.Device;
end
end
end
