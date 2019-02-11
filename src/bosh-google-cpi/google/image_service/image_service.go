package image

type Service interface {
	CreateFromURL(sourceURL string, sourceSha1 string, description string, licences []string) (string, error)
	CreateFromTarball(imagePath string, description string, licences []string) (string, error)
	Delete(id string) error
	Find(id string) (Image, bool, error)
}
