FROM python:3.13-slim AS builder

# Install build tools and system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc libffi-dev libssl-dev \
    && apt-get clean

# Copy the requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt

# Final runtime image
FROM python:3.13-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV TEST_MODE=false
ENV PORT=5000

# Set the working directory inside the container
WORKDIR /app

# Copy dependencies and application files
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY app.py .
COPY templates ./templates

# Expose the default port
EXPOSE $PORT

# Define the command to run the application
CMD ["sh", "-c", "python app.py --port $PORT"]
