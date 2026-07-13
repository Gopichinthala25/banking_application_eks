# gp3 as the cluster's DEFAULT StorageClass (provisioned by the EBS CSI driver,
# which Terraform installs as a managed add-on). gp3 is cheaper + faster than the
# EKS default gp2. Applied early (sync-wave -1) so PVCs bind against it.
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
    argocd.argoproj.io/sync-wave: "-1"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
allowVolumeExpansion: true
