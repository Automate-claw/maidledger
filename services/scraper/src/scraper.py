"""
Price Scraper Service
Crawls HKTVmall, Wellcome, ParknShop for daily price data
"""

import asyncio
import json
import logging
from datetime import datetime
from typing import Optional

import asyncpg
from playwright.async_api import async_playwright, Page

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Database config
DATABASE_URL = "postgresql://user:pass@localhost:5432/maidledger"

# Target supermarkets
SUPERMARKETS = {
    "hktvmall": "https://www.hktvmall.com",
    "wellcome": "https://www.wellcome.com.hk",
    "parknshop": "https://www.parknshop.com",
}

# Target categories for MVP
TARGET_CATEGORIES = ["fish", "pork", "beef", "chicken", "vegetables"]


class PriceScraper:
    """Main scraper class for supermarket price data"""

    def __init__(self, db_pool: asyncpg.Pool):
        self.db_pool = db_pool

    async def scrape_all(self) -> dict:
        """Main entry point - scrape all supermarkets"""
        results = {"success": 0, "failed": 0, "items": 0}

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)

            for name, url in SUPERMARKETS.items():
                try:
                    if name == "hktvmall":
                        count = await self._scrape_hktvmall(browser)
                    elif name == "wellcome":
                        count = await self._scrape_wellcome(browser)
                    elif name == "parknshop":
                        count = await self._scrape_parknshop(browser)
                    results["success"] += 1
                    results["items"] += count
                    logger.info(f"{name}: scraped {count} items")
                except Exception as e:
                    logger.error(f"{name} failed: {e}")
                    results["failed"] += 1

            await browser.close()

        return results

    async def _scrape_hktvmall(self, browser, category: str = "fish") -> int:
        """Scrape HKTVmall for specific category"""
        page = await browser.new_page()
        count = 0

        try:
            await page.goto(f"{SUPERMARKETS['hktvmall']}/s/{category}", timeout=30000)
            await page.wait_for_load_state("networkidle")

            # HKTVmall uses JS rendering, need to wait for product grid
            await page.wait_for_selector(".product-item", timeout=10000)

            products = await page.query_selector_all(".product-item")

            for product in products:
                try:
                    name = await product.query_selector(".product-name")
                    price = await product.query_selector(".price")

                    if name and price:
                        name_text = await name.inner_text()
                        price_text = await price.inner_text()

                        # Parse price (remove $ and convert)
                        price_value = self._parse_price(price_text)

                        await self._save_price(
                            supermarket="hktvmall",
                            category=category,
                            product_name=name_text.strip(),
                            price=price_value,
                            unit=self._extract_unit(price_text),
                            url=page.url,
                        )
                        count += 1
                except Exception as e:
                    logger.debug(f"Product parse error: {e}")
                    continue

        finally:
            await page.close()

        return count

    async def _scrape_wellcome(self, browser, category: str = "fish") -> int:
        """Scrape Wellcome Hong Kong"""
        page = await browser.new_page()
        count = 0

        try:
            # Wellcome uses a different URL structure
            await page.goto(
                f"{SUPERMARKETS['wellcome']}/en/{category}",
                timeout=30000
            )
            await page.wait_for_load_state("networkidle")

            # Wellcome product grid selector
            await page.wait_for_selector("[data-product-id]", timeout=10000)

            products = await page.query_selector_all("[data-product-id]")

            for product in products:
                try:
                    name_el = await product.query_selector(".product-name, .pname")
                    price_el = await product.query_selector(".price, .promo-price")

                    if name_el and price_el:
                        name_text = await name_el.inner_text()
                        price_text = await price_el.inner_text()

                        price_value = self._parse_price(price_text)

                        await self._save_price(
                            supermarket="wellcome",
                            category=category,
                            product_name=name_text.strip(),
                            price=price_value,
                            unit=self._extract_unit(price_text),
                            url=page.url,
                        )
                        count += 1
                except Exception as e:
                    logger.debug(f"Wellcome product error: {e}")
                    continue

        finally:
            await page.close()

        return count

    async def _scrape_parknshop(self, browser, category: str = "fish") -> int:
        """Scrape ParknShop"""
        page = await browser.new_page()
        count = 0

        try:
            await page.goto(
                f"{SUPERMARKETS['parknshop']}/en/{category}",
                timeout=30000
            )
            await page.wait_for_load_state("networkidle")
            await page.wait_for_selector(".product-tile", timeout=10000)

            products = await page.query_selector_all(".product-tile")

            for product in products:
                try:
                    name_el = await product.query_selector(".product-name")
                    price_el = await product.query_selector(".product-price")

                    if name_el and price_el:
                        name_text = await name_el.inner_text()
                        price_text = await price_el.inner_text()

                        price_value = self._parse_price(price_text)

                        await self._save_price(
                            supermarket="parknshop",
                            category=category,
                            product_name=name_text.strip(),
                            price=price_value,
                            unit=self._extract_unit(price_text),
                            url=page.url,
                        )
                        count += 1
                except Exception as e:
                    logger.debug(f"ParknShop product error: {e}")
                    continue

        finally:
            await page.close()

        return count

    def _parse_price(self, price_text: str) -> Optional[float]:
        """Extract numeric price from text like '$45.5/lb'"""
        import re
        match = re.search(r'[\$£]?\s*(\d+(?:\.\d{1,2})?)', price_text)
        if match:
            return float(match.group(1))
        return None

    def _extract_unit(self, price_text: str) -> str:
        """Extract unit from price text like '$45.5/lb'"""
        import re
        match = re.search(r'\/\s*(\w+)', price_text)
        if match:
            return match.group(1)
        return "unit"

    async def _save_price(
        self,
        supermarket: str,
        category: str,
        product_name: str,
        price: Optional[float],
        unit: str,
        url: str,
    ):
        """Save price to PostgreSQL"""
        if price is None:
            return

        async with self.db_pool.acquire() as conn:
            await conn.execute(
                """
                INSERT INTO price_data
                    (supermarket, category, product_name, price, unit, source_url, scraped_at)
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                ON CONFLICT (supermarket, category, product_name, DATE(scraped_at))
                DO UPDATE SET
                    price = EXCLUDED.price,
                    unit = EXCLUDED.unit,
                    scraped_at = EXCLUDED.scraped_at
                """,
                supermarket,
                category,
                product_name,
                price,
                unit,
                url,
                datetime.utcnow(),
            )


async def run_daily_scrape():
    """Main entry point for cron job"""
    logger.info("Starting daily price scrape")

    pool = await asyncpg.create_pool(DATABASE_URL, min_size=2, max_size=5)

    try:
        scraper = PriceScraper(pool)
        results = await scraper.scrape_all()
        logger.info(f"Scraping complete: {results}")
    finally:
        await pool.close()


if __name__ == "__main__":
    asyncio.run(run_daily_scrape())