#!/bin/bash
set -e

# Suppress xdg-open errors. Codespaces has no desktop environment,
# so any tool that tries to open a browser (e.g., quarto publish)
# would fail with a confusing error. This replaces xdg-open with
# a harmless no-op script.
printf '#!/bin/sh\nexit 0' | sudo tee /usr/local/bin/xdg-open > /dev/null
sudo chmod +x /usr/local/bin/xdg-open

# Install arf, a modern R console written in Rust. Provides syntax
# highlighting, fuzzy history search (Ctrl+R), and a better
# interactive experience than the default R terminal.
curl --proto '=https' --tlsv1.2 -LsSf \
  https://github.com/eitsupi/arf/releases/latest/download/arf-console-installer.sh | sh

# Install R packages needed for the course.
#   - tutorial.helpers: infrastructure for learnr-based tutorials
#   - quarto: R interface to Quarto for rendering and publishing
R -e 'install.packages(c("tutorial.helpers"))'
