package subnetwork

type Service interface {
	Find(id string, region string) (Subnetwork, error)
}
