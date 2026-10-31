# Logos de Pylo

Les variantes séparées sont dans App/Assets.xcassets/Brand.imageset/pylo-light.png et pylo-dark.png. Le catalogue sélectionne la variante selon l’apparence iOS ; AppIcon possède aussi sa variante sombre.

Les deux variantes ont été isolées avec l’outil imagegen intégré à partir du fichier fourni par l’auteur. Il s’agit de reconstructions fidèles, pas de recadrages garantis pixel pour pixel. Le fichier de référence original reste conservé dans Brand.imageset/brand.png.

Prompts utilisés : extraire uniquement le logo de gauche pour le thème clair, puis uniquement celui de droite pour le sombre ; conserver les ondes bleues, le pylône, les couleurs de fond, les proportions et la bordure ; retirer légendes et planche environnante ; produire un carré sans redessiner le concept. Les tailles d’icône ont ensuite été adaptées aux exigences du catalogue Xcode.

Prompts exacts transmis à imagegen :

```text
Edit target: supplied Pylo logo sheet. Extract ONLY the LEFT light-mode square app logo into one standalone square image. Preserve exactly the original blue radio waves, dark antenna, light near-white background, proportions and rounded square border. Tight square framing around the icon itself, no caption, no dark-mode logo, no surrounding sheet or black margins. This is an extraction, not a redesign. Output 1024x1024. Save the result for use as the light app logo.

Edit target: supplied Pylo logo sheet. Extract ONLY the RIGHT dark-mode square app logo into one standalone square image. Preserve exactly original blue radio waves, pale antenna, near-black background and rounded square border, proportions. Tight square framing around icon, NO caption, NO light-mode logo, NO surrounding sheet or black margins. Extraction only, not redesign. Output square 1024x1024.
```

## Icônes à fond perdu

Les logos ont ensuite été repris avec imagegen, en mode édition, pour enlever la grande marge et la bordure extérieure. Consigne : conserver le pylône et les trois ondes de chaque côté ; fond clair ou sombre jusqu’aux quatre coins du carré ; aucun cadre, aucune bordure, aucun carré arrondi ni marge extérieure ; symbole centré occupant environ 78 % du carré ; pas de texte ni d’ajout. Les fichiers de projet sont `App/Assets.xcassets/Brand.imageset/pylo-light.png` et `pylo-dark.png`, également déclinés en 1024 × 1024 dans AppIcon. Le masque arrondi est laissé à iOS.
