package bratsutils

import (
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/onsi/ginkgo/config"
	"github.com/onsi/gomega/gbytes"
	"github.com/onsi/gomega/gexec"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

const (
	mysqlDBType    = "mysql"
	postgresDBType = "postgres"
)

type ExternalDBConfig struct {
	Host     string
	Type     string
	User     string
	Password string
	DBName   string

	CACertPath     string
	ClientCertPath string
	ClientKeyPath  string

	ConnectionVarFile     string
	ConnectionOptionsFile string
}

var (
	outerBoshBinaryPath,
	boshBinaryPath,
	innerBoshPath,
	innerBoshJumpboxPrivateKeyPath,
	innerDirectorIP,
	innerDirectorUser,
	boshDirectorReleasePath,
	stemcellOS string
)

func Bootstrap() {
	outerBoshBinaryPath = AssertEnvExists("BOSH_BINARY_PATH")

	innerDirectorUser = "jumpbox"
	innerBoshPath = fmt.Sprintf("/tmp/inner-bosh/director/%d", config.GinkgoConfig.ParallelNode)
	boshBinaryPath = filepath.Join(innerBoshPath, "bosh")
	innerBoshJumpboxPrivateKeyPath = filepath.Join(innerBoshPath, "jumpbox_private_key.pem")
	innerDirectorIP = fmt.Sprintf("10.245.0.%d", 10+config.GinkgoConfig.ParallelNode)
	boshDirectorReleasePath = AssertEnvExists("BOSH_DIRECTOR_RELEASE_PATH")
	stemcellOS = AssertEnvExists("STEMCELL_OS")

	AssertEnvExists("BOSH_ENVIRONMENT")
	AssertEnvExists("BOSH_DEPLOYMENT_PATH")
}

func LoadExternalDBConfig(DBaaS string, mutualTLSEnabled bool, tmpCertDir string) *ExternalDBConfig {
	var databaseType string
	if strings.HasSuffix(DBaaS, mysqlDBType) {
		databaseType = mysqlDBType
	} else {
		databaseType = postgresDBType
	}

	config := ExternalDBConfig{
		Type:                  databaseType,
		Host:                  AssertEnvExists(fmt.Sprintf("%s_EXTERNAL_DB_HOST", strings.ToUpper(DBaaS))),
		User:                  AssertEnvExists(fmt.Sprintf("%s_EXTERNAL_DB_USER", strings.ToUpper(DBaaS))),
		Password:              AssertEnvExists(fmt.Sprintf("%s_EXTERNAL_DB_PASSWORD", strings.ToUpper(DBaaS))),
		DBName:                fmt.Sprintf("db_%s_%d", databaseType, config.GinkgoConfig.ParallelNode),
		ConnectionVarFile:     fmt.Sprintf("external_db/%s.yml", DBaaS),
		ConnectionOptionsFile: fmt.Sprintf("external_db/%s_connection_options.yml", DBaaS),
	}

	caContents := []byte(os.Getenv(fmt.Sprintf("%s_EXTERNAL_DB_CA", strings.ToUpper(DBaaS))))
	if len(caContents) == 0 {
		var err error
		caContents, err = exec.Command(outerBoshBinaryPath, "int", AssetPath(config.ConnectionVarFile), "--path", "/db_ca").Output()
		Expect(err).ToNot(HaveOccurred())
	}
	caFile, err := ioutil.TempFile(tmpCertDir, "db_ca")
	Expect(err).ToNot(HaveOccurred())

	defer caFile.Close()
	_, err = caFile.Write(caContents)
	Expect(err).ToNot(HaveOccurred())

	config.CACertPath = caFile.Name()

	if mutualTLSEnabled {
		clientCertContents := AssertEnvExists(fmt.Sprintf("%s_EXTERNAL_DB_CLIENT_CERTIFICATE", strings.ToUpper(DBaaS)))
		clientKeyContents := AssertEnvExists(fmt.Sprintf("%s_EXTERNAL_DB_CLIENT_PRIVATE_KEY", strings.ToUpper(DBaaS)))

		clientCertFile, err := ioutil.TempFile(tmpCertDir, "client_cert")
		Expect(err).ToNot(HaveOccurred())

		defer clientCertFile.Close()
		_, err = clientCertFile.Write([]byte(clientCertContents))
		Expect(err).ToNot(HaveOccurred())

		clientKeyFile, err := ioutil.TempFile(tmpCertDir, "client_key")
		Expect(err).ToNot(HaveOccurred())

		defer clientKeyFile.Close()
		_, err = clientKeyFile.Write([]byte(clientKeyContents))
		Expect(err).ToNot(HaveOccurred())

		config.ClientCertPath = clientCertFile.Name()
		config.ClientKeyPath = clientKeyFile.Name()
	}

	return &config
}

func DeleteDB(dbConfig *ExternalDBConfig) {
	if dbConfig == nil {
		return
	}

	if dbConfig.Type == mysqlDBType {
		deleteMySQL(dbConfig)
	} else if dbConfig.Type == postgresDBType {
		deletePostgres(dbConfig)
	}
}

func deleteMySQL(dbConfig *ExternalDBConfig) {
	args := []string{
		"-h",
		dbConfig.Host,
		fmt.Sprintf("--user=%s", dbConfig.User),
		fmt.Sprintf("--password=%s", dbConfig.Password),
		"-e",
		fmt.Sprintf("drop database if exists %s;", dbConfig.DBName),
		fmt.Sprintf("--ssl-ca=%s", dbConfig.CACertPath),
	}

	if dbConfig.ClientCertPath != "" || dbConfig.ClientKeyPath != "" {
		args = append(args,
			fmt.Sprintf("--ssl-cert=%s", dbConfig.ClientCertPath),
			fmt.Sprintf("--ssl-key=%s", dbConfig.ClientKeyPath),
			"--ssl-mode=VERIFY_CA",
		)
	} else {
		args = append(args, "--ssl-mode=VERIFY_IDENTITY")
	}

	session := ExecCommand(mysqlDBType, args...)
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))
}

func deletePostgres(dbConfig *ExternalDBConfig) {
	connstring := fmt.Sprintf("dbname=postgres host=%s user=%s password=%s sslrootcert=%s ",
		dbConfig.Host,
		dbConfig.User,
		dbConfig.Password,
		dbConfig.CACertPath,
	)

	if dbConfig.ClientCertPath != "" || dbConfig.ClientKeyPath != "" {
		connstring += fmt.Sprintf("sslcert=%s sslkey=%s sslmode=verify-ca ",
			dbConfig.ClientCertPath,
			dbConfig.ClientKeyPath,
		)
	} else {
		connstring += "sslmode=verify-full "
	}

	args := []string{
		connstring,
		"-c",
		fmt.Sprintf("drop database if exists %s;", dbConfig.DBName),
	}

	session := ExecCommand("psql", args...)
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))
}

func CreateDB(dbConfig *ExternalDBConfig) {
	if dbConfig == nil {
		return
	}

	if dbConfig.Type == mysqlDBType {
		createMySQL(dbConfig)
	} else if dbConfig.Type == postgresDBType {
		createPostgres(dbConfig)
	}
}

func createMySQL(dbConfig *ExternalDBConfig) {
	args := []string{
		"-h",
		dbConfig.Host,
		fmt.Sprintf("--user=%s", dbConfig.User),
		fmt.Sprintf("--password=%s", dbConfig.Password),
		"-e",
		fmt.Sprintf("drop database if exists %s; create database %s;", dbConfig.DBName, dbConfig.DBName),
		fmt.Sprintf("--ssl-ca=%s", dbConfig.CACertPath),
	}

	if dbConfig.ClientCertPath != "" || dbConfig.ClientKeyPath != "" {
		args = append(args,
			fmt.Sprintf("--ssl-cert=%s", dbConfig.ClientCertPath),
			fmt.Sprintf("--ssl-key=%s", dbConfig.ClientKeyPath),
			"--ssl-mode=VERIFY_CA",
		)
	} else {
		args = append(args, "--ssl-mode=VERIFY_IDENTITY")
	}

	session := ExecCommand(mysqlDBType, args...)
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))
}

func createPostgres(dbConfig *ExternalDBConfig) {
	connstring := fmt.Sprintf("dbname=postgres host=%s user=%s password=%s sslrootcert=%s ",
		dbConfig.Host,
		dbConfig.User,
		dbConfig.Password,
		dbConfig.CACertPath,
	)

	if dbConfig.ClientCertPath != "" || dbConfig.ClientKeyPath != "" {
		connstring += fmt.Sprintf("sslcert=%s sslkey=%s sslmode=verify-ca ",
			dbConfig.ClientCertPath,
			dbConfig.ClientKeyPath,
		)
	} else {
		connstring += "sslmode=verify-full "
	}

	args := []string{
		connstring,
		"-c",
		fmt.Sprintf("drop database if exists %s;", dbConfig.DBName),
	}

	session := ExecCommand("psql", args...)
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))

	args = []string{
		connstring,
		"-c",
		fmt.Sprintf("create database %s;", dbConfig.DBName),
	}

	session = ExecCommand("psql", args...)
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))
}

func AssertEnvExists(envName string) string {
	val, found := os.LookupEnv(envName)
	if !found {
		Fail(fmt.Sprintf("Expected %s", envName))
	}
	return val
}

func AssetPath(filename string) string {
	path, err := filepath.Abs("../assets/" + filename)
	Expect(err).ToNot(HaveOccurred())

	return path
}

func ExecCommand(binaryPath string, args ...string) *gexec.Session {
	session, err := gexec.Start(
		exec.Command(binaryPath, args...),
		GinkgoWriter,
		GinkgoWriter,
	)

	Expect(err).ToNot(HaveOccurred())

	return session
}

func StartInnerBosh(args ...string) {
	StartInnerBoshWithExpectation(false, "", args...)
}

func StartInnerBoshWithExpectation(expectedFailure bool, expectedErrorToMatch string, args ...string) {
	effectiveArgs := []string{strconv.Itoa(config.GinkgoConfig.ParallelNode)}
	effectiveArgs = append(effectiveArgs, args...)

	if stemcellOS == "ubuntu-xenial" {
		effectiveArgs = append(effectiveArgs, "-o", AssetPath("inner-bosh-xenial-ops.yml"))
	}

	cmd := exec.Command(
		fmt.Sprintf("../../../../../../../ci/docker/main-bosh-docker/start-inner-bosh-parallel.sh"),
		effectiveArgs...,
	)
	cmd.Env = os.Environ()

	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).ToNot(HaveOccurred())

	if expectedFailure {
		Eventually(session, 25*time.Minute).Should(gbytes.Say(expectedErrorToMatch))
		Eventually(session, 25*time.Minute).Should(gexec.Exit(1))
	} else {
		Eventually(session, 25*time.Minute).Should(gexec.Exit(0))
	}
}

func CreateAndUploadBOSHRelease() {
	cmd := exec.Command(
		fmt.Sprintf("../../../../../../../ci/docker/main-bosh-docker/create-and-upload-release.sh"),
		strconv.Itoa(config.GinkgoConfig.ParallelNode),
	)
	cmd.Env = os.Environ()
	cmd.Env = append(cmd.Env, fmt.Sprintf("bosh_release_path=%s", boshDirectorReleasePath))

	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).ToNot(HaveOccurred())
	Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
}

func StopInnerBosh() {
	session, err := gexec.Start(
		exec.Command(
			"../../../../../../../ci/docker/main-bosh-docker/destroy-inner-bosh.sh",
			strconv.Itoa(config.GinkgoConfig.ParallelNode),
		),
		GinkgoWriter,
		GinkgoWriter,
	)
	Expect(err).ToNot(HaveOccurred())
	Eventually(session, 15*time.Minute).Should(gexec.Exit(0))
}

func BoshDeploymentAssetPath(assetPath string) string {
	return filepath.Join(os.Getenv("BOSH_DEPLOYMENT_PATH"), assetPath)
}

func OuterBosh(args ...string) *gexec.Session {
	return ExecCommand(outerBoshBinaryPath, args...)
}

func Bosh(args ...string) *gexec.Session {
	return ExecCommand(boshBinaryPath, args...)
}

func UploadStemcell(stemcellURL string) {
	session := Bosh("-n", "upload-stemcell", stemcellURL)
	Eventually(session, 5*time.Minute).Should(gexec.Exit(0))
}

func UploadRelease(releaseURL string) {
	session := Bosh("-n", "upload-release", releaseURL)
	Eventually(session, 2*time.Minute).Should(gexec.Exit(0))
}

func InnerBoshDirectorName() string {
	return fmt.Sprintf("bosh-%d", config.GinkgoConfig.ParallelNode)
}

func InnerBoshWithExternalDBOptions(dbConfig *ExternalDBConfig) []string {
	options := []string{
		"-o", BoshDeploymentAssetPath("misc/external-db.yml"),
		"-o", BoshDeploymentAssetPath("experimental/db-enable-tls.yml"),
		"-o", AssetPath(dbConfig.ConnectionOptionsFile),
		"--vars-file", AssetPath(dbConfig.ConnectionVarFile),
		fmt.Sprintf("--var-file=db_ca=%s", dbConfig.CACertPath),
		"-v", fmt.Sprintf("external_db_host=%s", dbConfig.Host),
		"-v", fmt.Sprintf("external_db_user=%s", dbConfig.User),
		"-v", fmt.Sprintf("external_db_password=%s", dbConfig.Password),
		"-v", fmt.Sprintf("external_db_name=%s", dbConfig.DBName),
	}

	if dbConfig.ClientCertPath != "" || dbConfig.ClientKeyPath != "" {
		options = append(options,
			fmt.Sprintf("-o %s", BoshDeploymentAssetPath("experimental/db-enable-mutual-tls.yml")),
			fmt.Sprintf("-o %s", AssetPath("tls-skip-host-verify.yml")),
			fmt.Sprintf("--var-file=db_client_certificate=%s", dbConfig.ClientCertPath),
			fmt.Sprintf("--var-file=db_client_private_key=%s", dbConfig.ClientKeyPath),
		)
	}

	return options
}

func StemcellOS() string                     { return stemcellOS }
func BoshBinaryPath() string                 { return boshBinaryPath }
func OuterBoshBinaryPath() string            { return outerBoshBinaryPath }
func InnerDirectorIP() string                { return innerDirectorIP }
func InnerDirectorUser() string              { return innerDirectorUser }
func InnerBoshJumpboxPrivateKeyPath() string { return innerBoshJumpboxPrivateKeyPath }
