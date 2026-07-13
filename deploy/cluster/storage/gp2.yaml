# Un-default the gp2 StorageClass that EKS creates automatically, so gp3 is the
# single default (two defaults would make PVC binding ambiguous).
#
# This mirrors the EKS-provided gp2 spec exactly EXCEPT the is-default-class
# annotation — so Argo CD only patches that annotation and never touches gp2's
# immutable fields (provisioner/parameters/volumeBindingMode/reclaimPolicy).
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp2
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
    argocd.argoproj.io/sync-wave: "-1"
provisioner: kubernetes.io/aws-ebs
parameters:
  fsType: ext4
  type: gp2
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
