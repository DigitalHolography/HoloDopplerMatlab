function displaySplashScreen(versionStr, gitInfo)
% DISPLAYSPLASHSCREEN Display a splash screen without Java.
%   displaySplashScreen(versionStr)
%   displaySplashScreen(versionStr, gitInfo)

if nargin < 2
    gitInfo = '';
end

% Locate the logo next to this function.
appDir = fileparts(mfilename('fullpath'));
logoPath = fullfile(appDir, 'holoDopplerLogo.png');

if ~isfile(logoPath)
    warning('HoloDoppler:SplashScreen:LogoNotFound', ...
        'Splash logo not found: %s', logoPath);
    return;
end

splash = [];

try
    info = imfinfo(logoPath);
    logoWidth = double(info(1).Width);
    logoHeight = double(info(1).Height);

    % Fit the splash to the screen without enlarging the logo.
    screenSize = get(groot, 'ScreenSize');
    scale = min([1, ...
                     0.8 * screenSize(3) / logoWidth, ...
                     0.8 * screenSize(4) / logoHeight]);

    w = max(1, round(logoWidth * scale));
    h = max(1, round(logoHeight * scale));

    % Reserve a separate footer so text remains readable.
    hasGitInfo = strlength(string(gitInfo)) > 0;
    footerHeight = 55 + 25 * double(hasGitInfo);

    splash = uifigure( ...
        'Visible', 'off', ...
        'WindowStyle', 'alwaysontop', ...
        'Name', 'HoloDoppler', ...
        'Resize', 'off', ...
        'Color', [0.08 0.08 0.08], ...
        'Position', [100 100 w h + footerHeight]);

    % Delete the window on normal return or on an error.
    cleanup = onCleanup(@() closeSplash(splash));

    uiimage(splash, ...
        'ImageSource', logoPath, ...
        'ScaleMethod', 'fit', ...
        'Position', [0 footerHeight w h]);

    uilabel(splash, ...
        'Text', char(string(versionStr)), ...
        'Interpreter', 'none', ...
        'HorizontalAlignment', 'center', ...
        'FontName', 'Arial', ...
        'FontSize', 20, ...
        'FontWeight', 'bold', ...
        'FontColor', [1 1 1], ...
        'Position', [10 footerHeight - 40 max(1, w - 20) 30]);

    if hasGitInfo
        uilabel(splash, ...
            'Text', char(string(gitInfo)), ...
            'Interpreter', 'none', ...
            'HorizontalAlignment', 'center', ...
            'FontName', 'Arial', ...
            'FontSize', 12, ...
            'FontColor', [1 0.35 0.35], ...
            'Position', [10 10 max(1, w - 20) 25]);
    end

    movegui(splash, 'center');
    splash.Visible = 'on';
    drawnow;

    % Keep the original three-second display, but allow early closure.
    startTime = tic;

    while isgraphics(splash) && toc(startTime) < 3
        pause(0.05);
    end

catch ME
    closeSplash(splash);

    % A cosmetic splash-screen failure must not stop application startup.
    warning('HoloDoppler:SplashScreen:DisplayFailed', ...
        'Skipping splash screen: %s', ME.message);
end

end

function closeSplash(splash)
% CLOSESPLASH Safely delete the window, including after manual closure.

if ~isempty(splash) && isgraphics(splash)
    delete(splash);
end

end
