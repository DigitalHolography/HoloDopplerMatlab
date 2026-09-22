%% Figures de l'article sur le rapport de bandes Doppler
% Modifier uniquement cette section, puis exécuter ce script.

clearvars;
close all;
clc;

%% Entrées

% Fichier *_output.h5 produit par HoloDopplerMatlab avec le type d'image SH.
% On peut aussi indiquer le dossier contenant un unique fichier *_output.h5.
dataPath = "Z:\260310_CHOROID\260310_AUZ0752_1\260310_AUZ0752_1_HD\h5\260310_AUZ0752_1_HD_output.h5";

% Dossier dans lequel enregistrer les PNG, PDF, CSV et le fichier MAT.
outputDirectory = "D:\ARTICLE\figures_spectrales";

% Masques facultatifs. Chaque masque peut être :
%   - le chemin d'une image binaire PNG/TIF ;
%   - directement une matrice logique de même taille que /SH_power(:,:,1).
% Supprimer/commenter une ligne si le masque n'existe pas encore.
masks = [];
% masks.retinal_artery = "D:\MASQUES\RetinalArteryMask.png";
% masks.choroidal_artery = "D:\MASQUES\ChoroidalArteryMask.png";

% Sans masque, utiliser simplement :
% masks = [];

%% Paramètres de l'article

lowBandKHz  = [3 9];
highBandKHz = [9 18];

% 0 : aucune correction d'affichage.
% Une valeur > 0 applique uniquement aux cartes affichées la correction
% HoloDoppler image ./ imgaussfilt(image,sigma), avec conservation d'énergie.
displayFlatFieldSigma = 0;

% Limites temporelles facultatives, en secondes. [] affiche toute la vidéo.
timeLimits = [];

% États spectralement comparés. [] choisit automatiquement le maximum et
% le minimum du rapport lissé dans timeLimits. Pour imposer deux batchs :
systolicIndex = [];
diastolicIndex = [];

%% Analyse

results = make_band_figures( ...
    dataPath, masks, ...
    'OutputDirectory', outputDirectory, ...
    'LowBand', lowBandKHz, ...
    'HighBand', highBandKHz, ...
    'DisplayFlatFieldSigma', displayFlatFieldSigma, ...
    'TimeLimits', timeLimits, ...
    'SystolicIndex', systolicIndex, ...
    'DiastolicIndex', diastolicIndex, ...
    'Visible', "on", ...
    'SaveFIG', true);

%% Cas d'un ancien HDF5 sans métadonnées /SH_processing
% Remplacer l'appel précédent par celui-ci en renseignant les valeurs :
%
% results = make_band_figures( ...
%     dataPath, masks, ...
%     'OutputDirectory', outputDirectory, ...
%     'Fs', 37, 'FsUnit', "kHz", ...
%     'BatchSize', 512, ...
%     'BatchStride', 64, ...
%     'LowBand', lowBandKHz, ...
%     'HighBand', highBandKHz);
