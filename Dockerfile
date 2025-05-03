FROM python:3.11-slim-bookworm

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
# Set a default port (can be overridden by environment variable)
ENV PORT 5000

# Set the working directory inside the container
WORKDIR /app

# Update the package list and upgrade installed packages
RUN apt-get update && apt-get upgrade -y && apt-get clean

# Copy the requirements file
COPY requirements.txt /app/

# Install the dependencies and clean up the requirements file
RUN pip install --no-cache-dir -r requirements.txt \
    && rm requirements.txt

# Copy only the necessary files and directories
COPY app.py /app/
COPY templates /app/templates/

# Clean up any temporary files created during dependency installation
RUN rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Expose the default port
EXPOSE $PORT

# Define the command to run the application
CMD ["sh", "-c", "python app.py --port $PORT"]
