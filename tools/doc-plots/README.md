# Documentation Plot Generation

This directory owns matplotlib-generated PNG diagrams used by the figure-eight
and LQR controller documents.

Generate the diagrams from the repository root:

```bash
python3 -m venv /private/tmp/openotter-doc-plots-venv
/private/tmp/openotter-doc-plots-venv/bin/python -m pip install -r tools/doc-plots/requirements.txt
MPLCONFIGDIR=/private/tmp/openotter-mplconfig \
  /private/tmp/openotter-doc-plots-venv/bin/python tools/doc-plots/generate_control_diagrams.py
```

The output files are written to `docs/superpowers/specs/figures/`.
