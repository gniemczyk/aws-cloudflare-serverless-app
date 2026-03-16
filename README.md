# 🚀 AWS CLOUDFLARE SERVERLESS APP

Uniwersalny, skalowalny template backendowy zbudowany w architekturze **Serverless**, oparty na podejściu **Infrastructure as Code (IaC)**. Projekt prezentuje kompletny cykl życia aplikacji — od automatyzacji infrastruktury, przez bezpieczne API, po monitoring i system alertów. Może służyć jako baza pod dowolną aplikację backendową lub full‑stack.

## 📋 Spis treści
* [Architektura Systemu](#-architektura-systemu)
* [Wykorzystane Technologie](#-wykorzystane-technologie)
* [Infrastruktura jako Kod (Terraform)](#-infrastruktura-jako-kod-terraform)
* [CI/CD i Automatyzacja](#-cicd-i-automatyzacja)
* [Monitoring i Obsługa Awarii](#-monitoring-i-obsługa-awarii)
* [Cross-Region Monitoring](#-cross-region-monitoring)
* [Deep Health Checking](#-deep-health-checking-uptime-monitoring)
* [Bezpieczeństwo](#-bezpieczeństwo)
* [Jak uruchomić](#-jak-uruchomić)

---

## 🏗 Architektura Systemu

System działa w architekturze **event-driven**. Ruch użytkownika przechodzi przez Cloudflare, trafia do **AWS API Gateway**, które wywołuje funkcję **AWS Lambda** realizującą logikę biznesową. Dane przechowywane są w **DynamoDB**, a statyczny frontend serwowany jest z **AWS S3**.  
Całość stanowi elastyczny fundament pod dowolny projekt serverless.

---

## 🛠 Wykorzystane Technologie

### **Backend & Storage**
* **AWS Lambda (Python):** Bezserwerowa logika biznesowa skalująca się automatycznie.
* **AWS API Gateway (v2 HTTP):** Wysokowydajne wejście do API o niskich opóźnieniach.
* **AWS DynamoDB:** Zarządzana baza NoSQL o stałej wydajności.
* **AWS S3:** Hosting frontendu oraz backend stanu Terraform.

### **Networking & DNS**
* **Cloudflare:** DNS, CDN, SSL/TLS oraz optymalizacja ruchu.
* **Terraform Cloudflare Provider:** Automatyzacja rekordów DNS (CNAME) zsynchronizowana z AWS.
* **AWS Route 53:** Globalne health checks i monitoring dostępności.

### **DevOps & CI/CD**
* **Terraform:** Deklaratywna orkiestracja infrastruktury.
* **GitHub Actions:** Pipeline CI/CD umożliwiający pełną automatyzację wdrożeń.

---

## 💻 Infrastruktura jako Kod (Terraform)

Infrastruktura jest w pełni definiowana w plikach `.tf`, co zapewnia powtarzalność i łatwe odtwarzanie środowisk.

* **Modularność:** Parametryzacja przez `variables.tf` bez modyfikacji kodu.
* **State Management:** Przechowywanie stanu w S3.
* **Multi-Provider:** Integracja AWS i Cloudflare w jednym procesie wdrożeniowym.

---

## 🔄 CI/CD i Automatyzacja

Wdrożenie uruchamia się automatycznie po każdym `push` do gałęzi `main`.

1. **Init:** Inicjalizacja backendu i providerów.
2. **Validate:** Walidacja składni i logiki Terraform.
3. **Apply:** Automatyczne wdrożenie zmian (`-auto-approve`).
4. **Secrets Management:** Wrażliwe dane przekazywane jako `TF_VAR_` z GitHub Secrets.

### 📦 Publikacja Artefaktów
Każde zbudowanie aplikacji generuje artefakty dostępne w **Actions → Artifacts**:
* **Backend:** `backend-release-${{ run_number }}` (lambda.zip)
* **Frontend:** `frontend-release-${{ run_number }}` (statyczne pliki S3)

---

## 📈 Monitoring i Obsługa Awarii

Projekt zawiera gotowe mechanizmy **Observability**.

### **CloudWatch Dashboard**
Monitorowane są:
* **Lambda:** invocations, errors, duration
* **API Gateway:** count, 4xx, 5xx

### **System Alertowy (SNS)**
* **CloudWatch Alarm:** Wykrywa błędy `5xx` w API Gateway.
* **AWS SNS:** Wysyła powiadomienia e-mail o awariach.

### **DynamoDB Health Monitoring**
* **Throttling Alerts:** Wykrywanie odrzuconych zapytań.
* **Error Tracking:** Rozróżnienie błędów użytkownika i systemowych.

---

## 🌍 Cross-Region Monitoring

System wykorzystuje hybrydowy model monitoringu:

* **Global Alerting Hub (us-east-1):** Centralny punkt odbioru alertów SNS oraz alarmów Route 53.
* **Regional Monitoring (eu-central-1):** Alarmy dla Lambda, API Gateway i DynamoDB działające lokalnie dla niskich opóźnień.

---

## 🔍 Deep Health Checking (Uptime Monitoring)

* **Global Health Checks:** Route 53 monitoruje dostępność z wielu regionów.
* **Dedykowany Alarm Uptime:** Osobny alert dla frontendu (Website_Uptime_Down).

---

## 🔐 Bezpieczeństwo

* **IAM Least Privilege:** Lambda ma minimalne wymagane uprawnienia.
* **API Throttling:** Limity `burst` i `rate` chronią przed nadużyciami.
* **Security by Design:** Brak hardcoded sekretów, separacja danych wrażliwych.

---

## 🚀 Jak uruchomić?

1. Skopiuj repozytorium na swój profil GitHub.
2. Dodaj wymagane sekrety w ustawieniach repozytorium (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ZONE_ID`).  
   - CLOUDFLARE_API_TOKEN (Edit zone DNS)
3. Dodaj wymagane zmienne w ustawieniach repozytorium (`ALERT_EMAIL`, `AWS_REGION = eu-central-1`, `DB_HASH_KEY = DBKEYID`, `DB_NAME = DBAPPNAME`, `MAIN_DOMAIN = domena.pl`, `STATE_BUCKET_NAME = bucket-state-quv2x`, `SUB_DOMAIN = app-subdomain-name`, `SUB_DOMAIN_API = app-subdomain-name-api`).  
   - Wszystkie zmienne dopasuj do aplikacji backend/frontend.  
   - `STATE_BUCKET_NAME` musi być unikalny, pozostałe wartości są przykładowe.
4. Wypchnij dowolną zmianę do gałęzi `main`.
5. Po wdrożeniu otrzymasz e-maile z regionów US i EU — potwierdź subskrypcję SNS, aby aktywować alerty.

---

**Autor:** Grzegorz N  
**Data:** Marzec 2026
