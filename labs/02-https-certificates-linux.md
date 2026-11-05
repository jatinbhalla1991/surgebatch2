# Lab 2: HTTPS - Creating, Installing and Renewing Certificates (Linux)

**Goal:** Create a key and CSR, issue a certificate, install it on Nginx, and handle renewal/expiry.

## Prerequisites
Ubuntu/Debian VM or container with `openssl` and `nginx` (`sudo apt install -y openssl nginx`).

## Exercise 1 - TLS fundamentals
Inspect a live handshake and chain:
```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null | openssl x509 -noout -subject -issuer -dates
```
Questions: Who issued it? When does it expire? What is the chain of trust?

## Exercise 2 - Private key and CSR
```bash
sudo mkdir -p /etc/ssl/lab && cd /etc/ssl/lab
sudo openssl genrsa -out lab.key 2048
sudo openssl req -new -key lab.key -out lab.csr -subj "/C=IN/ST=State/L=City/O=Lab/CN=lab.local" \
  -addext "subjectAltName=DNS:lab.local,DNS:www.lab.local"
openssl req -in lab.csr -noout -text | head -30
```
The CSR is what you send to a CA; the key never leaves the server.

## Exercise 3 - Issue a certificate
Self-signed (acting as our own CA):
```bash
sudo openssl x509 -req -in lab.csr -signkey lab.key -days 30 -out lab.crt \
  -extfile <(printf "subjectAltName=DNS:lab.local,DNS:www.lab.local")
```
For a public site use Let's Encrypt instead: `sudo apt install certbot python3-certbot-nginx && sudo certbot --nginx -d your.domain`.

## Exercise 4 - Install on Nginx
```nginx
server {
    listen 443 ssl;
    server_name lab.local;
    ssl_certificate     /etc/ssl/lab/lab.crt;
    ssl_certificate_key /etc/ssl/lab/lab.key;
    ssl_protocols TLSv1.2 TLSv1.3;
}
server { listen 80; server_name lab.local; return 301 https://$host$request_uri; }
```
```bash
sudo chmod 600 /etc/ssl/lab/lab.key
sudo nginx -t && sudo systemctl reload nginx
echo "127.0.0.1 lab.local" | sudo tee -a /etc/hosts
curl -vk https://lab.local
```

## Exercise 5 - Renewal and expiry handling
```bash
openssl x509 -in /etc/ssl/lab/lab.crt -noout -enddate
openssl x509 -in /etc/ssl/lab/lab.crt -noout -checkend $((14*86400)) && echo OK || echo "Expires within 14 days"
```
1. Re-issue with a new `-days` value using the same key/CSR, replace `lab.crt`, reload Nginx, and confirm the new date.
2. Write a cron job that runs the `-checkend` check daily and logs/alerts on failure.
3. With certbot: `sudo certbot renew --dry-run` and check `systemctl list-timers | grep certbot`.

## Checkpoints
- [ ] Difference between key, CSR, certificate, and chain?
- [ ] Why `nginx -t` before reload?
- [ ] What happens to clients when a certificate expires?
