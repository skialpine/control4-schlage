"""Composer classification and Navigator proxy declarations."""

import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


class ComposerClassificationTest(unittest.TestCase):
    def test_account_and_lock_use_distinct_driver_roles(self):
        # Standalone combo drivers have no Navigator UI. Only the account is
        # standalone; the lock must instantiate Control4's external lock proxy.
        for name in ("schlage_account", "schlage_lock"):
            with self.subTest(driver=name):
                driver = ET.parse(ROOT / "drivers" / name / "driver.xml").getroot()
                self.assertEqual(driver.findtext("controlmethod"), "ip")
                self.assertEqual(driver.findtext("control"), "lua_gen")
                self.assertEqual(driver.findtext("driver"), "DriverWorks")
                if name == "schlage_account":
                    self.assertEqual(driver.findtext("combo"), "true")
                    self.assertIsNone(driver.find("proxies"))
                    self.assertFalse(
                        any(
                            p.findtext("name") == "Add Locks to Room"
                            for p in driver.findall("config/properties/property")
                        )
                    )
                    self.assertFalse(
                        any(
                            a.findtext("command") == "Add_Locks"
                            for a in driver.findall("config/actions/action")
                        )
                    )
                else:
                    self.assertIn(driver.findtext("combo"), (None, "false", "False"))
                    proxies = driver.findall("proxies/proxy")
                    properties = {
                        p.findtext("name"): p
                        for p in driver.findall("config/properties/property")
                    }
                    self.assertEqual(
                        properties["Schlage Account"].findtext("type"), "LIST"
                    )
                    self.assertEqual(properties["Lock"].findtext("type"), "LIST")
                    self.assertEqual(len(proxies), 1)
                    self.assertEqual(proxies[0].text, "lock")
                    self.assertEqual(proxies[0].get("proxybindingid"), "5001")
                    connection = driver.find("connections/connection[id='5001']")
                    self.assertIsNotNone(connection)
                    self.assertEqual(
                        connection.findtext("classes/class/classname"), "LOCK"
                    )
                    self.assertEqual(connection.findtext("consumer"), "False")
                    self.assertEqual(connection.findtext("type"), "2")
                    self.assertTrue(
                        all(
                            cap.text == "False"
                            for cap in driver.findall("capabilities/*")
                        )
                    )
                    self.assertEqual(
                        driver.findtext("composer_categories/category"), "Lock"
                    )


if __name__ == "__main__":
    unittest.main()
