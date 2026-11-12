# Lab 2: HTTPS - Creating, Installing and Renewing Certificates (Linux)

**Goal:** Understand how SSL/TLS and HTTPS work, then get hands-on practice creating a private key and CSR, issuing a certificate (both self-signed/self-CA and Let's Encrypt), installing it on a web server (Nginx and Apache), and setting up renewal/expiry monitoring so certificates never silently expire.

**Duration:** ~60-90 minutes

**What you'll learn / do:**
1. SSL/TLS and HTTPS fundamentals (hands-on inspection of a live handshake)
2. Creating certificates and certificate signing requests (CSRs) on Linux
3. Installing certificates on a web server
4. Certificate renewal and expiry handling (manual + automated)

---

## Prerequisites

- A Linux VM or container (Ubuntu/Debian commands shown; Dockerized alternative included below).
- `sudo` access.
- Basic familiarity with the command line.

Install the tools used in this lab:

```bash
sudo apt update
sudo apt install -y openssl nginx curl
```

> **No Linux box handy?** Spin one up quickly with Docker:
> ```bash
> docker run -it --rm -p 8443:443 -p 8080:80 --name https-lab ubuntu:22.04 bash
> # inside the container:
> apt update && apt install -y openssl nginx curl sudo
> ```
> (Replace `sudo` with nothing, or just omit `sudo` for commands below, since you're root in the container.)

Verify your toolchain before starting:

```bash
openssl version
nginx -v
```

Expected output looks like:
```
OpenSSL 3.0.2 15 Mar 2022 (Library: OpenSSL 3.0.2 15 Mar 2022)
nginx version: nginx/1.18.0 (Ubuntu)
```

---

## Part 1 - SSL/TLS and HTTPS Fundamentals

### 1.1 Concepts (read before you run commands)

| Term | What it means |
|---|---|
| **TLS** | Transport Layer Security - the protocol that encrypts traffic between client and server. "SSL" is the old name (SSL 2.0/3.0 are deprecated/insecure); modern deployments use TLS 1.2 or 1.3. |
| **HTTPS** | HTTP running inside a TLS tunnel (default port 443 instead of 80). |
| **Asymmetric (public/private key) crypto** | A key *pair*: the **private key** stays secret on the server; the **public key** is embedded in the certificate and shared with everyone. Data encrypted with the public key can only be decrypted with the private key (and vice versa for signatures). |
| **Symmetric crypto** | Fast encryption using one shared "session key". TLS uses asymmetric crypto only to securely *negotiate* a symmetric session key, then switches to symmetric encryption for the actual data (because it's much faster). |
| **Certificate (cert)** | A signed document binding a public key to an identity (a domain name), issued and digitally signed by a Certificate Authority (CA). |
| **CSR (Certificate Signing Request)** | A request file containing your public key + identity info, which you send to a CA to get a signed certificate. Generated from your private key; the private key itself is never sent anywhere. |
| **CA (Certificate Authority)** | A trusted entity (e.g., Let's Encrypt, DigiCert) that verifies you control a domain and signs a certificate for it. Your OS/browser ships a list of trusted "root CAs". |
| **Chain of trust** | Leaf certificate → Intermediate CA certificate(s) → Root CA certificate. Browsers trust the root; the chain proves the leaf cert was signed (directly or transitively) by that root. |
| **CN / SAN** | Common Name (legacy, single hostname) and Subject Alternative Name (modern, list of hostnames/IPs a cert is valid for). Browsers today **require** SAN - CN alone is ignored. |
| **TLS handshake (simplified)** | 1) Client says hello with supported TLS versions/ciphers. 2) Server replies with its certificate + chosen cipher. 3) Client validates the cert chain against trusted roots, checks hostname/SAN and expiry. 4) Client & server derive a shared symmetric session key (via the key exchange algorithm). 5) Encrypted application data (HTTP) flows. |

### 1.2 Hands-on: Inspect a live HTTPS handshake

Connect to a real site and dump the certificate it presents:

```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates
```

Expected output (values will vary):
```
subject=CN = example.com
issuer=C = US, O = DigiCert Inc, CN = DigiCert Global G3 TLS ECC SHA384 2020 CA1
notBefore=Jan 15 00:00:00 2025 GMT
notAfter=Feb 15 23:59:59 2026 GMT
```

Now look at the full handshake details - protocol version, cipher suite negotiated, and the certificate chain depth:

```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null | grep -E "Protocol|Cipher|depth|verify"
```

You should see something like `Protocol  : TLSv1.3`, `Cipher    : TLS_AES_256_GCM_SHA384`, and `Verify return code: 0 (ok)`.

Dump the **entire** certificate (subject, issuer, validity, SANs, public key, signature algorithm):

```bash
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -text
```

Look specifically for the `X509v3 Subject Alternative Name` and `X509v3 Basic Constraints` (`CA:FALSE` on a leaf cert) sections.

**Questions to answer (write down your answers):**
- Who issued this certificate, and is it a root or intermediate CA?
- When does it expire? How many days from today?
- What TLS version and cipher suite were negotiated?
- What hostnames (SANs) is this certificate valid for?

---

## Part 2 - Creating Certificates and CSRs on Linux

### 2.1 Set up a working directory

```bash
sudo mkdir -p /etc/ssl/lab
cd /etc/ssl/lab
```

### 2.2 Generate a private key

RSA 2048-bit (widely compatible):

```bash
sudo openssl genrsa -out lab.key 2048
sudo chmod 600 lab.key
```

> **Modern alternative:** Elliptic-curve keys are smaller and faster. If you want to try it instead:
> ```bash
> sudo openssl ecparam -name prime256v1 -genkey -noout -out lab.key
> ```

Inspect the key you just created:

```bash
openssl rsa -in lab.key -noout -text | head -5
```

You'll see the key size (`Private-Key: (2048 bit, 2 primes)`) and the modulus/exponent.

### 2.3 Create a CSR config file (recommended over `-subj` for multi-SAN certs)

```bash
cat <<'EOF' | sudo tee lab-csr.cnf
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[dn]
C  = IN
ST = State
L  = City
O  = Lab
CN = lab.local

[req_ext]
subjectAltName = @alt_names

[alt_names]
DNS.1 = lab.local
DNS.2 = www.lab.local
EOF
```

### 2.4 Generate the CSR from the key + config

```bash
sudo openssl req -new -key lab.key -out lab.csr -config lab-csr.cnf
```

### 2.5 Verify the CSR

```bash
openssl req -in lab.csr -noout -text
```

Confirm you can see:
- `Subject: ... CN=lab.local`
- `Requested Extensions: X509v3 Subject Alternative Name: DNS:lab.local, DNS:www.lab.local`
- `Signature Algorithm: sha256WithRSAEncryption`

Also verify the CSR's public key matches your private key (their modulus hashes must match):

```bash
openssl req -in lab.csr -noout -pubkey | openssl md5
openssl rsa -in lab.key -pubout | openssl md5
```

Both commands should print the **same** hash - this proves the CSR was generated from this exact key.

> **Key takeaway:** The CSR (public key + identity) is what you send to a CA. The private key **never leaves the server**.

---

## Part 3 - Issuing a Certificate

You have two realistic paths. Do Option A first (it works fully offline and teaches you how a CA signs things), then read Option B for the real-world production path.

### Option A - Act as your own mini Certificate Authority (recommended for this lab)

This is more realistic than a plain self-signed cert because it mirrors how a real CA signs your CSR, and lets you build a trust chain.

**1. Create a root CA key and self-signed CA certificate:**

```bash
cd /etc/ssl/lab
sudo openssl genrsa -out ca.key 4096
sudo openssl req -x509 -new -nodes -key ca.key -sha256 -days 3650 -out ca.crt \
  -subj "/C=IN/ST=State/L=City/O=Lab-Root-CA/CN=Lab Root CA"
```

**2. Use the CA to sign your CSR (this issues `lab.crt`):**

```bash
cat <<'EOF' | sudo tee lab-ext.cnf
subjectAltName = DNS:lab.local,DNS:www.lab.local
basicConstraints = CA:FALSE
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
EOF

sudo openssl x509 -req -in lab.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out lab.crt -days 397 -sha256 -extfile lab-ext.cnf
```

> Note: `-days 397` matches the current max lifetime enforced by browsers for publicly-trusted certs (useful habit even in a lab).

**3. Verify the issued certificate and the chain:**

```bash
openssl x509 -in lab.crt -noout -text | grep -A1 "Subject:\|Issuer:\|Subject Alternative Name"
openssl verify -CAfile ca.crt lab.crt
```

Expected: `lab.crt: OK` - this proves `lab.crt` was signed by `ca.crt` and the signature is valid.

**4. (Optional) Trust your lab CA locally so `curl`/browser stop warning:**

```bash
sudo cp ca.crt /usr/local/share/ca-certificates/lab-root-ca.crt
sudo update-ca-certificates
```

### Option B - Real-world production path: Let's Encrypt (free, publicly trusted)

For a real internet-facing domain, use ACME via Certbot instead of self-signing:

```bash
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your.domain -d www.your.domain
```

Certbot will automatically obtain the cert, edit your Nginx config, and reload it. We'll simulate the renewal behavior of this path in Part 4.

---

## Part 4 - Installing the Certificate on a Web Server

### 4.1 Nginx

Lock down the key's permissions first (private keys should never be world-readable):

```bash
sudo chmod 600 /etc/ssl/lab/lab.key
sudo chown root:root /etc/ssl/lab/lab.key /etc/ssl/lab/lab.crt
```

Create a site config:

```bash
cat <<'EOF' | sudo tee /etc/nginx/sites-available/lab.local
server {
    listen 443 ssl;
    server_name lab.local www.lab.local;

    ssl_certificate     /etc/ssl/lab/lab.crt;
    ssl_certificate_key /etc/ssl/lab/lab.key;

    # If using Option A (your own mini-CA), clients validating against ca.crt
    # need the full chain; for a real CA, concatenate cert + intermediate here.
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    add_header          Strict-Transport-Security "max-age=63072000" always;

    root /var/www/html;
    index index.html;
}

server {
    listen 80;
    server_name lab.local www.lab.local;
    return 301 https://$host$request_uri;
}
EOF

sudo ln -sf /etc/nginx/sites-available/lab.local /etc/nginx/sites-enabled/lab.local
```

**Always test the config before reloading** - a typo here can take the whole server down:

```bash
sudo nginx -t
```

Expected: `nginx: configuration file /etc/nginx/nginx.conf test is successful`

Reload (not `restart`, so existing connections aren't dropped):

```bash
sudo systemctl reload nginx
```

Point a local hostname at this server and test:

```bash
echo "127.0.0.1 lab.local www.lab.local" | sudo tee -a /etc/hosts
curl -vk https://lab.local
```

`-k` skips cert trust validation (expected, since it's self-/lab-signed). You should see the HTTP response and, in the verbose handshake log, `SSL certificate verify result: ... ` plus the negotiated protocol/cipher.

Now test **with** validation, using your CA (should succeed without `-k`):

```bash
curl -v --cacert /etc/ssl/lab/ca.crt https://lab.local
```

Expected: no certificate error, and the page loads.

### 4.2 Apache (alternative/additional practice)

If you want to practice on Apache instead/also:

```bash
sudo apt install -y apache2
sudo a2enmod ssl
cat <<'EOF' | sudo tee /etc/apache2/sites-available/lab-ssl.conf
<VirtualHost *:443>
    ServerName lab.local
    ServerAlias www.lab.local
    SSLEngine on
    SSLCertificateFile    /etc/ssl/lab/lab.crt
    SSLCertificateKeyFile /etc/ssl/lab/lab.key
    DocumentRoot /var/www/html
</VirtualHost>
EOF
sudo a2ensite lab-ssl
sudo apachectl configtest && sudo systemctl reload apache2
```

### 4.3 Common installation pitfalls to check

- **Permission denied reading the key:** the web server user (`www-data`) must be able to read `lab.key`; owning it `root:root` with `600` works because Nginx/Apache master processes start as root and drop privileges after binding, but double-check with `sudo nginx -t` which will surface read errors.
- **SAN/hostname mismatch:** if `curl`/browser complains the cert isn't valid for the name you're requesting, confirm `-servername`/URL hostname is in the cert's SAN list (Part 2.5).
- **Wrong chain order:** when installing a CA-issued (not self-signed) cert, `ssl_certificate` must contain the **leaf cert followed by any intermediate certs**, concatenated in that order, e.g. `cat your_domain.crt intermediate.crt > fullchain.crt`.

---

## Part 5 - Certificate Renewal and Expiry Handling

### 5.1 Check current expiry

```bash
openssl x509 -in /etc/ssl/lab/lab.crt -noout -enddate
```

### 5.2 Scripted expiry check (what monitoring tools do under the hood)

`-checkend <seconds>` returns success only if the cert is valid for at least that many more seconds:

```bash
openssl x509 -in /etc/ssl/lab/lab.crt -noout -checkend $((14*86400)) \
  && echo "OK - valid for 14+ more days" \
  || echo "WARNING - expires within 14 days"
```

Wrap it into a reusable monitoring script:

```bash
cat <<'EOF' | sudo tee /usr/local/bin/check-cert-expiry.sh
#!/usr/bin/env bash
CERT="/etc/ssl/lab/lab.crt"
DAYS=14
if ! openssl x509 -in "$CERT" -noout -checkend $((DAYS*86400)); then
  echo "[$(date)] ALERT: $CERT expires within $DAYS days!" | tee -a /var/log/cert-check.log
  # In production: send an email/Slack/webhook alert here.
  exit 1
fi
echo "[$(date)] OK: $CERT is valid for more than $DAYS days." >> /var/log/cert-check.log
EOF
sudo chmod +x /usr/local/bin/check-cert-expiry.sh
sudo /usr/local/bin/check-cert-expiry.sh
```

### 5.3 Manual renewal (same key/CSR, re-issue with your mini-CA)

```bash
cd /etc/ssl/lab
sudo openssl x509 -req -in lab.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out lab.crt -days 90 -sha256 -extfile lab-ext.cnf
openssl x509 -in lab.crt -noout -dates
sudo nginx -t && sudo systemctl reload nginx
```

Confirm the new `notAfter` date is further out, and that the live server now serves the renewed cert:

```bash
echo | openssl s_client -connect lab.local:443 -servername lab.local 2>/dev/null | openssl x509 -noout -enddate
```

### 5.4 Automate the check with cron

```bash
( crontab -l 2>/dev/null; echo "0 6 * * * /usr/local/bin/check-cert-expiry.sh" ) | crontab -
crontab -l
```

This runs the expiry check daily at 06:00 and logs to `/var/log/cert-check.log`.

### 5.5 The production path: Certbot auto-renewal

If you set up Let's Encrypt in Part 3 Option B, Certbot already installs a renewal timer:

```bash
sudo certbot renew --dry-run
systemctl list-timers | grep certbot
cat /etc/cron.d/certbot 2>/dev/null || systemctl cat certbot.timer
```

Certbot renews automatically once a certificate is within 30 days of expiry, and reloads the web server for you via a deploy hook.

### 5.6 What happens when a certificate actually expires (see it yourself)

Issue a cert that's already expired to observe client-side failure behavior:

```bash
cd /etc/ssl/lab
sudo openssl x509 -req -in lab.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out lab-expired.crt -days -1 -sha256 -extfile lab-ext.cnf
openssl verify -CAfile ca.crt lab-expired.crt
```

Expected: `error 10 at 0 depth lookup: certificate has expired` - this is exactly the error a browser/client surfaces (e.g. `NET::ERR_CERT_DATE_INVALID`) when a site's cert isn't renewed in time, and it **hard-blocks** access rather than degrading gracefully.

---

## Troubleshooting Reference

| Symptom | Likely cause | Fix |
|---|---|---|
| `nginx -t` fails with "cannot load certificate" | Wrong path or permissions on `.crt`/`.key` | Check path, `chmod 600` the key, confirm ownership |
| `curl: (60) SSL certificate problem: self signed certificate` | Expected for self-signed/lab CA certs | Use `-k` for testing, or `--cacert ca.crt` to validate properly |
| Browser: `ERR_CERT_COMMON_NAME_INVALID` | Hostname not in SAN list | Regenerate CSR/cert with correct `DNS.x` entries (Part 2.3) |
| `NET::ERR_CERT_DATE_INVALID` | Certificate expired or clock skew | Renew certificate (Part 5.3) or fix server time (`timedatectl`) |
| `certbot renew` does nothing | Cert not yet within the 30-day renewal window | Expected behavior; force with `certbot renew --force-renewal` to test |

---

## Checkpoints (self-check before moving on)

- [ ] Can you explain the difference between a private key, a CSR, a certificate, and a chain?
- [ ] Why does TLS use asymmetric crypto only during the handshake, then switch to symmetric encryption?
- [ ] Why run `nginx -t` before every `reload`?
- [ ] What exact error does a client show when a certificate has expired, and why is it a hard failure rather than a warning?
- [ ] What's the difference between the manual renewal you just did and what Certbot automates for you?

## Clean up

```bash
sudo rm -f /etc/nginx/sites-enabled/lab.local
sudo systemctl reload nginx
sudo sed -i '/lab.local/d' /etc/hosts
sudo rm -rf /etc/ssl/lab /usr/local/share/ca-certificates/lab-root-ca.crt /usr/local/bin/check-cert-expiry.sh
sudo update-ca-certificates
crontab -l | grep -v check-cert-expiry.sh | crontab -
```
