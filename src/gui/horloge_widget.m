function horloge_widget()
% HORLOGE_WIDGET  Horloge analogique en base 6 (UTC) avec date séximale
%   - Cadran de 36 graduations (une par pseudo‑heure)
%   - Trois aiguilles : pseudo‑heures, pseudo‑minutes, pseudo‑secondes
%   - Affichage numérique : heure base 6 (HH:MM:SS) + date base 6
%   - Date séximale : Saison, JourSemaine, Semaine Sxx, NumJour
%   - Mise à jour toutes les 0.1 s, temps universel UTC+0
%   Lancement : horloge_widget()

% --- Création de la figure ---
fig = figure('Name', 'Horloge base 6 UTC', ...
    'NumberTitle', 'off', ...
    'MenuBar', 'none', ...
    'ToolBar', 'none', ...
    'Position', [200 200 400 460], ... % hauteur ajustée
    'Resize', 'off');

ax = axes('Parent', fig, ...
    'Position', [0.1 0.25 0.8 0.65], ... % laisse place aux textes
    'DataAspectRatio', [1 1 1], ...
    'XLim', [-1.2 1.2], 'YLim', [-1.2 1.2], ...
    'Visible', 'off');

% --- Dessiner le cadran (36 graduations, pas de 10°) ---
hold(ax, 'on');
theta = linspace(0, 2 * pi, 200);
plot(cos(theta), sin(theta), 'k', 'LineWidth', 2);

for k = 0:35
    angle = deg2rad(90 - k * 10); % 0 en haut

    if mod(k, 6) == 0
        % Marque principale toutes les 6 pseudo‑heures
        x1 = 0.80 * cos(angle); y1 = 0.80 * sin(angle);
        x2 = 1.00 * cos(angle); y2 = 1.00 * sin(angle);
        line([x1 x2], [y1 y2], 'Color', 'k', 'LineWidth', 2.5);
        % Étiquette en base 6 (00, 10, 20, 30, 40, 50)
        label = sprintf('%d0', k / 6);
        text(1.12 * cos(angle), 1.12 * sin(angle), label, ...
            'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
    else
        % Petite graduation
        x1 = 0.93 * cos(angle); y1 = 0.93 * sin(angle);
        x2 = 1.00 * cos(angle); y2 = 1.00 * sin(angle);
        line([x1 x2], [y1 y2], 'Color', [0.5 0.5 0.5], 'LineWidth', 1);
    end

end

hold(ax, 'off');

% --- Aiguilles ---
centerX = 0; centerY = 0;
hPseudoHour = line('Parent', ax, 'XData', [centerX centerX], 'YData', [centerY centerY], ...
    'Color', 'r', 'LineWidth', 4);
hPseudoMin = line('Parent', ax, 'XData', [centerX centerX], 'YData', [centerY centerY], ...
    'Color', 'b', 'LineWidth', 3);
hPseudoSec = line('Parent', ax, 'XData', [centerX centerX], 'YData', [centerY centerY], ...
    'Color', 'k', 'LineWidth', 1.5);

% --- Affichages numériques ---
% 1) Heure séximale (base 6) – grande
hBase6 = uicontrol('Style', 'text', ...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', [0.2 0.14 0.6 0.08], ...
    'String', '00:00:00', ...
    'FontSize', 22, 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor', get(fig, 'Color'));

% 2) Date séximale – en dessous
hDate = uicontrol('Style', 'text', ...
    'Parent', fig, ...
    'Units', 'normalized', ...
    'Position', [0.05 0.03 0.9 0.08], ...
    'String', 'Automne Lundi S0 0', ...
    'FontSize', 12, 'FontWeight', 'normal', ...
    'HorizontalAlignment', 'center', ...
    'BackgroundColor', get(fig, 'Color'));

% --- Mise à jour des aiguilles et des textes ---
function updateClock(~, ~)
    % Temps UTC actuel avec fractions de seconde
    nowUTC = datetime('now', 'TimeZone', 'UTC');
    realSec = seconds(timeofday(nowUTC)); % secondes depuis minuit UTC

    % Conversion en pseudo‑secondes (1 jour = 46656 pseudo‑secondes)
    pseudoTotal = realSec * 27/50; % car 46656/86400 = 27/50

    % Pseudo‑heures, minutes, secondes (continues, 0–36)
    pseudoSec = mod(pseudoTotal, 36);
    pseudoMin = mod(pseudoTotal / 36, 36);
    pseudoHour = mod(pseudoTotal / (36 * 36), 36);

    % Angles (0 = midi en haut, sens horaire, 10° par unité)
    secAngle = deg2rad(90 - pseudoSec * 10);
    minAngle = deg2rad(90 - pseudoMin * 10);
    hourAngle = deg2rad(90 - pseudoHour * 10);

    % Longueurs des aiguilles
    Lhour = 0.55;
    Lmin = 0.75;
    Lsec = 0.85;

    set(hPseudoHour, 'XData', [centerX, Lhour * cos(hourAngle)], ...
        'YData', [centerY, Lhour * sin(hourAngle)]);
    set(hPseudoMin, 'XData', [centerX, Lmin * cos(minAngle)], ...
        'YData', [centerY, Lmin * sin(minAngle)]);
    set(hPseudoSec, 'XData', [centerX, Lsec * cos(secAngle)], ...
        'YData', [centerY, Lsec * sin(secAngle)]);

    % Heure séximale formatée (HH:MM:SS)
    set(hBase6, 'String', [base6str(floor(pseudoHour)), ':', ...
                       base6str(floor(pseudoMin)), ':', ...
                       base6str(floor(pseudoSec))]);

    % --- Date séximale ---
    epoch = datetime(2025, 9, 21, 'TimeZone', 'UTC'); % jour 0, Automne
    daysSinceEpoch = floor(days(datetime(nowUTC) - datetime(epoch)));
    dayOfYear = mod(daysSinceEpoch, 365); % 0 … 364

    % Saison (6 périodes)
    seasonNames = {'Automne', 'Brume', 'Hiver', 'Printemps', 'Verne', 'Été'};
    seasonBounds = [0, 60, 120, 180, 240, 300, 365];

    for sIdx = 1:6

        if dayOfYear < seasonBounds(sIdx + 1)
            season = seasonNames{sIdx};
            break;
        end

    end

    % Jour de la semaine
    dowNames = {'Lundi', 'Eaudi', 'Terdi', 'Airdi', 'Feudi', 'Soldi'};
    dow = dowNames{mod(dayOfYear, 6) + 1};

    % Numéro du jour en base 6 (sans padding)
    dayNumStr = dec2base(dayOfYear, 6);

    dateStr = sprintf('%s %s %s', season, dow, dayNumStr);
    set(hDate, 'String', dateStr);
end

% --- Utilitaire : entier 0‑35 → chaîne base 6 sur 2 chiffres ---
function str6 = base6str(n)
    tmp = dec2base(n, 6);

    if numel(tmp) < 2
        tmp = ['0' tmp];
    end

    str6 = tmp;
end

% --- Timer (mise à jour toutes les 0.1 s) ---
t = timer('ExecutionMode', 'fixedRate', ...
    'Period', 0.1, ...
    'TimerFcn', @updateClock, ...
    'BusyMode', 'drop');

updateClock(); % premier rafraîchissement immédiat

% --- Arrêt propre du timer à la fermeture de la fenêtre ---
fig.CloseRequestFcn = @(~, ~) closeFigure();

function closeFigure()
    stop(t);
    delete(t);
    delete(fig);
end

start(t);
end
