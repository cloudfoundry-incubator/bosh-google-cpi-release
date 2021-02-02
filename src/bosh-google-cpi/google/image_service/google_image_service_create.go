package image

import (
	"fmt"
	"os"

	bosherr "github.com/cloudfoundry/bosh-utils/errors"

	"google.golang.org/api/compute/v1"
	"google.golang.org/api/storage/v1"
)

func (i GoogleImageService) cleanUp(id string) {
	if err := i.Delete(id); err != nil {
		i.logger.Debug(googleImageServiceLogTag, "Failed cleaning up Google Image '%s': %#v", id, err)
	}
}

func (i GoogleImageService) CreateFromURL(sourceURL string, sourceSha1 string, description string) (string, error) {
	uuidStr, err := i.uuidGen.Generate()
	if err != nil {
		return "", bosherr.WrapErrorf(err, "Generating random Google Image name")
	}

	imageName := fmt.Sprintf("%s-%s", googleImageNamePrefix, uuidStr)
	image, err := i.create(imageName, description, sourceURL, sourceSha1)
	if err != nil {
		return "", bosherr.WrapErrorf(err, "Creating Google Image from URL")
	}

	return image, nil
}

func (i GoogleImageService) CreateFromTarball(imagePath string, description string) (string, error) {
	uuidStr, err := i.uuidGen.Generate()
	if err != nil {
		return "", bosherr.WrapErrorf(err, "Generating random Google Image name")
	}

	// Create a temporary bucket
	imageName := fmt.Sprintf("%s-%s", googleImageNamePrefix, uuidStr)
	bucket := &storage.Bucket{
		Name: imageName,
	}

	i.logger.Debug(googleImageServiceLogTag, "Creating Google Storage Bucket with params: %#v", bucket)
	if _, err = i.storageService.Buckets.Insert(i.project, bucket).Do(); err != nil {
		return "", bosherr.WrapErrorf(err, "Creating Google Storage Bucket")
	}
	defer i.deleteBucket(imageName)

	// Upload the image file to the previously created bucket
	objectName := fmt.Sprintf("%s.tar.gz", imageName)

	var objectAccessControl []*storage.ObjectAccessControl
	objectAcl := &storage.ObjectAccessControl{
		Bucket: imageName,
		Entity: "allUsers",
		Object: objectName,
		Role:   "READER",
	}
	objectAccessControl = append(objectAccessControl, objectAcl)

	object := &storage.Object{
		Name: objectName,
		Acl:  objectAccessControl,
	}

	imageFile, err := os.Open(imagePath)
	if err != nil {
		return "", bosherr.WrapErrorf(err, "Reading stemcell image file")
	}
	defer imageFile.Close()

	i.logger.Debug(googleImageServiceLogTag, "Creating Google Storage Object with params: %#v", object)
	imageObject, err := i.storageService.Objects.Insert(imageName, object).Media(imageFile).Do()
	if err != nil {
		return "", bosherr.WrapErrorf(err, "Creating Google Storage Object")
	}
	defer i.deleteObject(imageName, objectName)

	// Create the image
	image, err := i.create(imageName, description, imageObject.MediaLink, "")
	if err != nil {
		return "", bosherr.WrapErrorf(err, "Creating Google Image from Tarball")
	}

	return image, nil
}

func (i GoogleImageService) create(name string, description string, sourceURL string, sourceSha1 string) (string, error) {
	if description == "" {
		description = googleImageDescription
	}

	rawdisk := &compute.ImageRawDisk{
		Source:       sourceURL,
		Sha1Checksum: sourceSha1,
	}

	image := &compute.Image{
		Name:        name,
		Description: description,
		RawDisk:     rawdisk,
		GuestOsFeatures: []*compute.GuestOsFeature{
			{Type: "MULTI_IP_SUBNET"},
		},
		StorageLocations: "EU",
	}

	i.logger.Debug(googleImageServiceLogTag, "Creating Google Image with params: %#v", image)
	operation, err := i.computeService.Images.Insert(i.project, image).Do()
	if err != nil {
		return "", bosherr.WrapErrorf(err, "Failed to create Google Image")
	}

	if _, err = i.operationService.Waiter(operation, "", ""); err != nil {
		i.cleanUp(image.Name)
		return "", bosherr.WrapErrorf(err, "Failed to create Google Image")
	}

	return image.Name, nil
}

func (i GoogleImageService) deleteObject(bucketName string, objectName string) error {
	i.logger.Debug(googleImageServiceLogTag, "Deleting Google Storage Object '%s' from Google Storage Bucket '%s'", objectName, bucketName)
	if err := i.storageService.Objects.Delete(bucketName, objectName).Do(); err != nil {
		return bosherr.WrapErrorf(err, "Deleting Google Storage Object")
	}

	return nil
}

func (i GoogleImageService) deleteBucket(bucketName string) error {
	i.logger.Debug(googleImageServiceLogTag, "Deleting Google Storage Bucket '%s'", bucketName)
	if err := i.storageService.Buckets.Delete(bucketName).Do(); err != nil {
		return bosherr.WrapErrorf(err, "Deleting Google Storage Bucket")
	}

	return nil
}
