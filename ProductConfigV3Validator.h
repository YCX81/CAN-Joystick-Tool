#pragma once

#include <QJsonObject>
#include <QStringList>

class ProductConfigV3Validator
{
public:
    struct Result {
        bool ok = false;
        QStringList errors;
    };

    static Result validate(const QJsonObject &config);
};
