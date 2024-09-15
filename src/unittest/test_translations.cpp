/*
Minetest
Copyright (C) 2024 y5nw <y5nw@protonmail.com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation; either version 2.1 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
*/

#include "translation.h"
#include "filesys.h"
#include "content/subgames.h"
#include "catch.h"

#define CONTEXT L"context"
#define TEXTDOMAIN_PO L"translation_po"
#define TEST_PO_NAME "translation_po.de.po"
#define TEST_MO_NAME "translation_mo.de.mo"

static std::string read_translation_file(const std::string &filename)
{
		auto gamespec = findSubgame("devtest");
		REQUIRE(gamespec.isValid());
		auto path = gamespec.gamemods_path + (DIR_DELIM "testtranslations" DIR_DELIM "test_locale" DIR_DELIM) + filename;
		std::string content;
		REQUIRE(fs::ReadFile(path, content));
		return content;
}

TEST_CASE("test translations")
{
	SECTION("Plural-Forms function for translations")
	{
		auto form = GettextPluralForm::parseHeaderLine(L"Plural-Forms: nplurals=3; plural= (n-1+1)<=1 ? n||1?0:1 : 1?(!!2):2;");
		REQUIRE(form);
		REQUIRE(form->size() == 3);
		CHECK((*form)(0) == 0);
		CHECK((*form)(1) == 0);
		CHECK((*form)(2) == 1);
	}

	SECTION("PO file parser")
	{
		Translations translations;
		translations.loadTranslation(TEST_PO_NAME, read_translation_file(TEST_PO_NAME));

		CHECK(translations.size() == 5);
		CHECK(translations.getTranslation(TEXTDOMAIN_PO, L"foo") == L"bar");
		CHECK(translations.getTranslation(TEXTDOMAIN_PO, L"Untranslated") == L"Untranslated");
		CHECK(translations.getTranslation(TEXTDOMAIN_PO, L"Fuzzy") == L"Fuzzy");
		CHECK(translations.getTranslation(TEXTDOMAIN_PO, L"Multi\\line\nstring") == L"Multi\\\"li\\ne\nresult");
		CHECK(translations.getTranslation(TEXTDOMAIN_PO, L"Wrong order") == L"Wrong order");
		CHECK(translations.getPluralTranslation(TEXTDOMAIN_PO, L"Plural form", 1) == L"Singular result");
		CHECK(translations.getPluralTranslation(TEXTDOMAIN_PO, L"Singular form", 0) == L"Plural result");
		CHECK(translations.getPluralTranslation(TEXTDOMAIN_PO, L"Partial translation", 1) == L"Partially translated");
		CHECK(translations.getPluralTranslation(TEXTDOMAIN_PO, L"Partial translations", 2) == L"Partial translations");
		CHECK(translations.getTranslation(CONTEXT, L"With context") == L"Has context");
	}

	SECTION("MO file parser")
	{
		Translations translations;
		translations.loadTranslation(TEST_MO_NAME, read_translation_file(TEST_MO_NAME));

		CHECK(translations.size() == 2);
		CHECK(translations.getTranslation(CONTEXT, L"With context") == L"Has context");
		CHECK(translations.getPluralTranslation(CONTEXT, L"Plural form", 1) == L"Singular result");
		CHECK(translations.getPluralTranslation(CONTEXT, L"Singular form", 0) == L"Plural result");
	}
}
