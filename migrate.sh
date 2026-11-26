#!/usr/bin/env bash
# Phase 1 : réorganisation en src/ (dossiers ordinaires, pas de packages).
# Usage : DRY_RUN=1 bash migrate.sh   (simulation)
#         bash migrate.sh             (exécution)
set -euo pipefail

DRY_RUN="${DRY_RUN:-0}"
git rev-parse --show-toplevel >/dev/null          # doit être dans un dépôt git
cd "$(git rev-parse --show-toplevel)"
[ "$DRY_RUN" = "1" ] || [ -z "$(git status --porcelain)" ] || {
  echo "Arbre de travail non propre : commit ou stash d'abord."; exit 1; }

run() { if [ "$DRY_RUN" = "1" ]; then echo "[dry] $*"; else "$@"; fi; }

# mv_to <dossier_cible> <fichier>... : git mv, ignore les fichiers absents
mv_to() {
  local dest="$1"; shift
  run mkdir -p "$dest"
  for f in "$@"; do
    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      run git mv "$f" "$dest/"
    else
      echo "  (absent, ignoré) $f"
    fi
  done
}

# ---------- core : orchestration ----------
mv_to src/core \
  HoloDopplerClass.m \
  ParallelPoolManager.m \
  Tools/RunningAveragesHolder.m

# ---------- render : physique ----------
mv_to src/render \
  RenderingClass.m \
  Rendering/intercorrel.m \
  Rendering/propagation_kernelAngularSpectrum.m \
  Rendering/propagation_kernelFresnel.m \
  Rendering/short_time_ICA.m \
  Rendering/short_time_PCA.m \
  Rendering/svd_filter.m \
  Tools/twin_image_removal_.m \
  Tools/morlet1D_transform_3rdDim.m \
  Tools/pad3DToSquare.m \
  Tools/diskMask.m \
  Tools/fftfreq.m \
  Tools/autofocus.m \
  Tools/fit_spectrum_voigt.m

# ---------- images : construction des types d'image ----------
mv_to src/images \
  Imaging/ImageType.m Imaging/ImageTypeList.m Imaging/cdf.m \
  Imaging/color_energy_ratio.m Imaging/composite.m \
  Imaging/construct_colored_image.m Imaging/construct_directional_image.m \
  Imaging/cumulant.m Imaging/directional.m Imaging/energy_ratio.m \
  Imaging/fit_spectrum.m Imaging/flat_field_correction.m \
  Imaging/moment0.m Imaging/moment1.m Imaging/moment2.m \
  Imaging/spectral_entropy.m Imaging/spectral_negentropy.m \
  Imaging/spectrum_ploting.m

# ---------- io : lecteurs de fichiers ----------
mv_to src/io \
  ReaderClasses/CineDatastore.m ReaderClasses/CineReader.m \
  ReaderClasses/HoloDatastore.m ReaderClasses/HoloReader.m \
  ReaderClasses/unpack_u12_u10.m

# ---------- params : schéma et configuration ----------
mv_to src/params \
  Interface/HDParamSchema.m \
  Interface/getFileParameters.m \
  Interface/generateParametersJson.m

# ---------- export : sauvegardes ----------
mv_to src/export \
  Saving/export_h5_string.m Saving/export_h5_video.m \
  Saving/generate_image.m Saving/generate_video.m \
  Interface/toImageSource.m

# ---------- register : recalage ----------
mv_to src/register \
  Saving/Registering/registerImagesCrossCorrelation.m \
  Saving/Registering/register_video_from_reference.m \
  Tools/calc_registration_from_views.m

# ---------- gui : interface et fenêtres d'exploration ----------
mv_to src/gui \
  Tools/AdvancedPanel.m Tools/SplashScreen.m Tools/displaySplashScreen.m \
  horloge_widget.m \
  FolderManagement/FolderManagementUI.m \
  FolderManagement/get_highest_number_in_files.m \
  Interface/show_ref_disk.m
mv_to src/gui/explore \
  Tools/ExploreAp.m Tools/ExploreAp2.m Tools/ExploreSH.m \
  Tools/ExploreSHbroadening.m Tools/ExploreZ.m

# ---------- util ----------
mv_to src/util \
  Tools/MEdisp.m Tools/releaseVersion.m

# ---------- mex (Windows) ----------
mv_to src/mex Tools/unwrap_2d.mexw64 Tools/unwrap_2d2.mexw64

# ---------- scripts hors bibliothèque ----------
mv_to tools ExploreSHbroadeningFromH5.m

# ---------- suppressions ----------
for f in Tools/Copy_of_ExploreAp.m; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && run git rm -q "$f"
done

# ---------- OPTIONNEL (décommente après avoir patché les chemins) ----------
run mkdir -p configs
run git mv StandardConfigs/* configs/        # et remplacer 'StandardConfigs' dans le code
run mkdir -p assets
run git mv holoDopplerLogo.png assets/
run git rm -q Tools/holoDopplerLogo.png      # doublon (même taille : 66468 octets)

echo
echo "Fichiers .m restants hors src/ :"
git ls-files '*.m' | grep -v '^src/' || true
echo
echo "Dossiers vides à supprimer éventuellement :"
find . -type d -empty -not -path './.git/*' || true

[ "$DRY_RUN" = "1" ] || git commit -qm "Phase 1: reorganise sources into src/ (no code changes)"