
```
Package: Check status of LaTeX packages
Author:  Jianrui Lyu <tolvjr@163.com>
License: The LaTeX Project Public License 1.3c
```

This tool finds out all `.sty` and `.cls` files in folders
```
TEXMF/tex/generic/
TEXMF/tex/latex/
TEXMF/tex/lualatex/
TEXMF/tex/xelatex/
```
and tries to check if they could be successfully compiled on current TeX distribution, using the following minimal tex documents
```latex
% for somename.cls file
\documentclass{somename}
\begin{document}
TEST
\end{document}
```
```latex
% for somename.sty file
\documentclass{article}
\usepackage{somename}
\begin{document}
TEST
\end{document}
```

To use it, you only need to run
```
texlua pkgstatus.lua
```
and the names of failed packages will be written to`faillist.txt`.

The names of previously failed packages have been added to `ignorelist.txt`. To update it, you can remove it, run the tool, and rename `faillist.txt` as `ignorelist.txt`.

The following customization files may be useful:
  - `pkgstatus-list-exc.lua`: for excluding files in texlive/miktex packages.
  - `pkgstatus-list-inc.lua`: for including files in texlive/miktex packages.
  - `pkgstatus-rule-cls.lua`: for modifying compilation rules of `.cls` files.
  - `pkgstatus-rule-sty.lua`: for modifying compilation rules of `.sty` files.
