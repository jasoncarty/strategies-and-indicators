# SSL Certificates Directory

This directory is for SSL certificates when running Nginx with HTTPS.

## Setup Instructions

### For Development
1. Generate self-signed certificates:
```bash
cd docker/nginx/ssl
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
```

### For Production
1. Obtain SSL certificates from a trusted CA (Let's Encrypt, etc.)
2. Place the certificates here:
   - `cert.pem` - Your SSL certificate
   - `key.pem` - Your private key
3. Uncomment the HTTPS server block in `nginx.conf`

## File Structure
```
docker/nginx/ssl/
├── README.md          # This file
├── cert.pem           # SSL certificate (create or add)
└── key.pem            # Private key (create or add)
```

## Security Notes
- Never commit real SSL certificates to version control
- Use environment variables for production certificates
- Regularly rotate certificates
- Keep private keys secure
