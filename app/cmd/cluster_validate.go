package cmd

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/arctaruslimited/fractal/app/internal/pkg/control"
	"github.com/arctaruslimited/fractal/app/internal/pkg/utils"
	"github.com/jedib0t/go-pretty/v6/table"
	"github.com/jedib0t/go-pretty/v6/text"
	"github.com/schollz/progressbar/v3"
	"github.com/spf13/cobra"
)

var clusterValidateCmd = &cobra.Command{
	Use:        "validate <cluster>",
	Short:      "Validates the resources of a cluster",
	Args:       cobra.MinimumNArgs(1),
	ArgAliases: []string{"cluster"},
	Run: func(cmd *cobra.Command, args []string) {
		cluster := args[0]
		repo := control.NewRepository(config.Flake)

		var pbar *progressbar.ProgressBar
		if config.PrettyOutput {
			pbar = progressbar.NewOptions(-1,
				progressbar.OptionSpinnerType(14),
				progressbar.OptionEnableColorCodes(true),
			)
		}

		if pbar != nil {
			pbar.Describe("validating cluster resources")
		}

		tmpResult, err := utils.AsyncProgressWait(func() (interface{}, error) {
			return repo.ValidateCluster(cluster)
		}, pbar)

		if err != nil {
			log.Fatal(err)
		}

		// clear progress bar before rendering
		if pbar != nil {
			pbar.Clear()
		}

		result := *tmpResult.(*control.ValidationResult)

		if config.JsonOutput {
			bytes, err := json.MarshalIndent(result, "", "  ")
			if err != nil {
				log.Fatal(err)
			}
			fmt.Println(string(bytes))
		} else {
			writer := table.NewWriter()
			writer.SetOutputMirror(os.Stdout)
			writer.AppendHeader(table.Row{"Type", "Resource", "Message"})
			writer.SetColumnConfigs([]table.ColumnConfig{
				{Name: "Type", WidthMax: 10},
				{Name: "Resource", WidthMax: 80},
				{Name: "Message", WidthMax: 40},
			})

			// append resources to the table
			for name, value := range result.Resources {
				_type := value.Type
				if _type == "success" {
					_type = text.FgGreen.Sprint(_type)
				} else if _type == "warning" {
					_type = text.FgYellow.Sprint(_type)
				} else if _type == "error" {
					_type = text.FgRed.Sprint(_type)
				}

				writer.AppendRow(table.Row{_type, name, value.Message})
			}

			// format the "summary" text
			var summary string
			if result.Counts.Error > 0 {
				summary = text.FgRed.Sprint("error")
			} else if result.Counts.Warning > 0 {
				summary = text.FgYellow.Sprint("warning")
			} else {
				summary = text.FgGreen.Sprint("success")
			}

			writer.AppendSeparator()
			writer.AppendRow(table.Row{
				text.FgGreen.Sprint(summary),
				fmt.Sprintf(
					"%d resources validated successfully, %d warnings, %d errors",
					result.Counts.Success, result.Counts.Warning, result.Counts.Error,
				), "N/A",
			})

			writer.Render()
		}

		if result.Counts.Error > 0 {
			os.Exit(1)
		}
	},
}

func init() {
	clusterCmd.AddCommand(clusterValidateCmd)
}