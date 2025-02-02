# **Learning Kyverno Policies**

## **What is Kyverno?**
Kyverno is a **policy engine** for Kubernetes. It lets you **validate, mutate, and generate** Kubernetes resources using policies. You can use Kyverno to enforce **security, compliance, and best practices** in your cluster.

## **Purpose of This Repository**
This repository helps you **learn how to write and apply Kyverno policies**. It contains **taskfiles, scripts, and examples** to guide you through writing and applying policies.

## **Prerequisites**
Ensure you have the following installed on **Linux**:
- `kubectl`
- `helm`
- `kustomize`
- `kind`
- `task`
- `dnsmasq` (for local DNS resolution)

To set up `dnsmasq`, follow [this guide](https://github.com/josephaw1022/MetalLb-Kind) and run:
```bash
task dnsmasq:up
```
To tear it down:
```bash
task dnsmasq:down
```

## **How to Use This Repository**
1. **List available tasks:**
   ```bash
   task
   ```
2. **Quickly set up a Kyverno test environment:**
   ```bash
   task quickstart
   ```
   This will:
   - Create a **Kind** cluster with necessary components.
   - Install **Kyverno**.
   - Deploy a **Helm release** to test Kyverno policies.
   - Run **tests** to verify that the policies work as expected.

That's it—you're ready to start working with Kyverno policies. 🚀