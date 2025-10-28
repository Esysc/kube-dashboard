#!/bin/bash

# Create a temporary directory
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

echo "Downloading kubent..."
curl -L -o kubent.tar.gz https://github.com/doitintl/kube-no-trouble/releases/download/0.7.3/kubent-0.7.3-linux-amd64.tar.gz

echo "Extracting kubent..."
tar -xzf kubent.tar.gz

echo "Installing kubent..."
chmod +x kubent
mkdir -p ~/.local/bin
mv kubent ~/.local/bin/

echo "Cleaning up..."
cd - > /dev/null
rm -rf "$TEMP_DIR"

echo "Kubent installed to ~/.local/bin/kubent"
echo "Make sure ~/.local/bin is in your PATH or use ~/.local/bin/kubent to run it"

# Test if it works
if ~/.local/bin/kubent --version &> /dev/null; then
    echo "Kubent installation successful!"
    echo "$(~/.local/bin/kubent --version)"
else
    echo "Kubent installation failed. Please check the error messages above."
fi
