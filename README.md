# IONOS-Core-DNS-cert-manager-lets-encrypt-K8s-webhook
A scripted cert-manager, IONOS Core DNS webhook, installation on IONOS Managed Kubernetes for autmatic installation and update of TLS certificates via the free "Let's Encrypt" ACME service. 

Pre-requisites: 
1. An IONOS Managed Kubernetes instance deplpoyed (i.e. https://dcd.ionos.com/latest/ etc)
2. A functioning Linux management host with Kubectl working towards the IONOS Managed Kubernetes cluster and Helm installed
3. A reserved IP address from the IONOS DCD for the demo NGINX ingress and webserver in Kubernetes 
4. IONOS Core account with registered DNS names that require TLS certificates issued automatically.  (i.e. https://login.ionos.de/ or https://login.ionos.co.uk/ etc)
5. IONOS Core DNS functioning API access - this requires activation in your account. Once completed, you will have two important pieces of data: the Public prefix and the secret.

There are two main components: 
a) The main cluster installation that results in a functioning "ClusterIssuer" in the cert-manager namespace, so that various other cluster applications in seperate namespaces may reference this issuer to execute the issueing of new TLS certs, and automatic renewal of expired TLS certificates for your particular domain.
This component utilises the opensource IONOS Webhook for Core DNS and lLt's Encrypt originally written by fabmade.de.  I have complied this and stored the executable in my public Duckerhub account.
b) A sample NGINX ingress and NGINX web server container configured with your domain name.  This namespace is where the TLS certificate will be issued to and stored in the K8s cluster.

Each installation has a preset values YAML file that enable you to enter your custom variables, such as your IONOS Core DNS secret for accessing the API, the domain name in the DNS that the TLS is to be issued for, the desired namespace name in Kubernetes cluster etc.

For part a) there is a "cluster-values.yaml" file, that you can populate with your specific values
  # Global Identity
  acme_email: "your@email.com"

  # IONOS Core DNS API Authentication
  ionos_public_prefix: "3dec2bdec6954d3e9d24a504a5912345"
  ionos_secret: "dyKrAWstgLBE-WmXc3FwV0-4J4KlnbnhRROQJmJb3BH5_Sa0IhKD0oxZrIlIgx0Abx1Ldnaz9xuw4wX123456"

  # Shared Infrastructure Names
  issuer_name: "ionos-letsencrypt-issuer"

for part b) there is the "site-values.yaml" file, that you can edit and populate with your specific values for the web application:
  # site-values.yaml
  site:
    namespace: "my-web-app"
    domain: "www.example.com"
    alt_domain: "example.com"
    # This is your IONOS reserved/static IP
    loadBalancerIP: "123.123.123.123"
    issuer_name: "ionos-letsencrypt-issuer"
    tls_secret_name: "my-web-app-tls-secret-www"
