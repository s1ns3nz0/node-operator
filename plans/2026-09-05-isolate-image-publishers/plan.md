# Isolated image publishers

1. Build OCI images in package-read jobs and transfer short-lived artifacts.
2. Allow a package-write publisher only on main.
3. Recompute and verify the source input digest and image label before every push.
4. Validate workflow syntax and repository policy checks.
