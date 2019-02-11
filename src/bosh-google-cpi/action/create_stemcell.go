package action

import (
	"fmt"

	bosherr "github.com/cloudfoundry/bosh-utils/errors"

	"bosh-google-cpi/google/image_service"
)

const googleInfrastructure = "google"

type CreateStemcell struct {
	imageService image.Service
}

func NewCreateStemcell(
	imageService image.Service,
) CreateStemcell {
	return CreateStemcell{
		imageService: imageService,
	}
}

func (cs CreateStemcell) Run(stemcellPath string, cloudProps StemcellCloudProperties) (StemcellCID, error) {
	var err error
	var description, stemcell string

	if cloudProps.Infrastructure != googleInfrastructure {
		return "", bosherr.Errorf("Creating stemcell: Invalid '%s' infrastructure", cloudProps.Infrastructure)
	}

	if cloudProps.Name != "" && cloudProps.Version != "" {
		description = fmt.Sprintf("%s/%s", cloudProps.Name, cloudProps.Version)
	}

	switch {
	case cloudProps.ImageURL != "":
		stemcell = cloudProps.ImageURL
	case cloudProps.SourceURL != "":
		stemcell, err = cs.imageService.CreateFromURL(cloudProps.SourceURL, cloudProps.SourceSha1, description, cloudProps.Licences)
	default:
		stemcell, err = cs.imageService.CreateFromTarball(stemcellPath, description, cloudProps.Licences)
	}
	if err != nil {
		return "", bosherr.WrapError(err, "Creating stemcell")
	}

	return StemcellCID(stemcell), nil
}
