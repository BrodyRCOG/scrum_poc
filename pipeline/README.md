# How to use Issue Intake Pipeline

---

## Install requirements
``` pip install -r pipeline/requirements.txt ```

---

## Get certification files

### Install Cryptography

``` pip install cryptography ```

### Export Your Corporate Root Certificate

1. Open **Chrome** or **Edge** and navigate to `https://api.github.com`
2. Click the 🔒 padlock in the address bar
3. Click **Connection is secure** → **Certificate is valid**
4. Go to the **Details** tab → click **Export**
5. Save the file as `corporate-ca.crt` to `C:\certs\`
    - Create the `C:\certs\` folder first if it does not exist

### Generate the Combined Certificate Bundle

Run the following Python script from your terminal:

```
python -c "
import ssl, os
from cryptography import x509
from cryptography.hazmat.primitives import serialization

# Pull all trusted root certs from the Windows certificate store
ctx = ssl.create_default_context()
der_certs = ctx.get_ca_certs(binary_form=True)

with open('C:/certs/combined-ca.crt', 'wb') as out:
    for der in der_certs:
        cert = x509.load_der_x509_certificate(der)
        out.write(cert.public_bytes(serialization.Encoding.PEM))

    # Append the corporate CA cert
    with open('C:/certs/corporate-ca.crt', 'rb') as corp:
        out.write(corp.read())

print(f'Done: {len(der_certs)} system certs + corporate CA written to C:/certs/combined-ca.crt')
"
```

This produces `C:\certs\combined-ca.crt` — a single PEM file containing:
- All Windows trusted root certificates
- Your corporate CA certificate

---

### Add the Bundle to Your `.env`

Open your `.env` file in the project root and add or update this line:

```text
REQUESTS_CA_BUNDLE=C:\certs\combined-ca.crt
```

---

## Run pipeline

```
# Ingest one file
python pipeline/import_to_issues.py sample_requirements.txt

# Ingest multiple files
python pipeline/import_to_issues.py sample_requirements_one.txt sample_requirements_two.md

#Ingest directory of files
python pipeline/import_to_issues.py directory/*

# Ingest directory and files
python pipeline/import_to_issues.py sample_requirements.txt directory/*
```