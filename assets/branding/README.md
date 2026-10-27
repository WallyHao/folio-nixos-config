# README wordmark

The title uses **TeX Gyre Pagella Regular**, and the original Chinese subtitle
uses **LXGW WenKai GB Regular**. Letterforms are SVG outlines, so readers do not
need to install either font. Both images have transparent backgrounds.

The README selects light/dark artwork with GitHub's supported
[`picture` element](https://github.blog/changelog/2022-05-19-specify-theme-context-for-images-in-markdown-beta/).
Alternative text preserves the full title and subtitle.

Font sources:

- [TeX Gyre Pagella](https://www.gust.org.pl/projects/e-foundry/tex-gyre/pagella): GUST Font License.
- [LXGW WenKai GB](https://github.com/lxgw/LxgwWenkaiGB): SIL Open Font License 1.1.

To regenerate, install these fonts plus Fontconfig and Python with `fontTools`,
then run `python3 scripts/render-readme-header.py` from the repository root.
The generated files contain artwork only; no font files are distributed.
