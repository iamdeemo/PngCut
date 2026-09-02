using System.IO;
using NUnit.Framework;

namespace PngCut.Tests;

public class SharedContractDocumentTests
{
    [TestCase("behavior.json")]
    [TestCase("discovery-cases.json")]
    [TestCase("output-policy-cases.json")]
    [TestCase("error-catalog.json")]
    [TestCase("engine-manifest.json")]
    public void Shared_contract_document_is_copied_to_test_output(string name)
    {
        Assert.That(File.Exists(Path.Combine(TestContext.CurrentContext.TestDirectory, "Contracts", name)), Is.True);
    }

    [Test]
    public void Behavior_contract_version_is_one()
    {
        var json = File.ReadAllText(Path.Combine(TestContext.CurrentContext.TestDirectory, "Contracts", "behavior.json"));
        var document = new System.Web.Script.Serialization.JavaScriptSerializer()
            .Deserialize<System.Collections.Generic.Dictionary<string, object>>(json);

        Assert.That(document["version"], Is.EqualTo(1));
    }
}
